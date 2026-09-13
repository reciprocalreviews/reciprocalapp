-- Completeness: the events that moved money, granted authority, or changed what somebody was
-- responsible for, and told nobody.
--
-- The rule this works to: any action somebody would otherwise only discover by logging in and
-- looking for new activity deserves an optional email. Measured against it, the platform had
-- roughly thirty silences. The loudest were financial — gifts, mints, and minting authority
-- all moved without a word, while every FAILURE around them (a decline, a venue short of
-- tokens) wrote to somebody — and the most consequential were governance: a role could be
-- deleted out from under its volunteers, and priority-0 editorial authority could move
-- between roles, with nothing sent to anyone affected.
--
-- Most of the new producers are in the application layer and need no migration. Two things
-- here do: the seed, which is the database's copy of what may be silenced, and
-- create_volunteer, which is where an administrator seats somebody in a role directly.

--------------------------------------
-- create_volunteer now writes to a scholar an administrator has seated directly.
--
-- That path told them nothing at all: _notify_new_volunteer is deliberately suppressed for it
-- (an admin's own action is not news to the admins) and RoleInvite only fires where there IS
-- an invitation. So a scholar acquired a venue commitment, and possibly a welcome grant with
-- it, and the only way to find out was to read their own profile.

create or replace function public.create_volunteer (
	_scholarid uuid,
	_roleid uuid,
	_accepted boolean,
	_compensate boolean,
	_papers integer
) returns jsonb language plpgsql security definer
set
	search_path=public,
	pg_temp as $function$
declare
	_caller uuid;
	_venueid uuid;
	_invited boolean;
	_existing_count integer;
	_volunteer_id uuid;
	_granted integer := 0;
begin
	-- Identify and require an authenticated caller.
	_caller := (select auth.uid());
	if _caller is null then
		raise exception 'Authentication required';
	end if;

	-- Look up the role's venue and whether it is invite-only.
	select venueid, invited into _venueid, _invited from public.roles where id = _roleid;
	if _venueid is null then
		raise exception 'Role not found';
	end if;

	-- A venue admin may add anyone; otherwise a scholar may only add themselves,
	-- and only to a role that is not invite-only.
	if not (public.isAdmin(_venueid) or (_caller = _scholarid and not _invited)) then
		raise exception 'You are not authorized to volunteer for this role';
	end if;

	-- No duplicate volunteering for the same role. RR004 surfaces the specific
	-- "already volunteered" message.
	if exists (select 1 from public.volunteers where scholarid = _scholarid and roleid = _roleid) then
		raise exception 'Already volunteered for this role' using errcode = 'RR004';
	end if;

	-- Welcome tokens are standing policy of one venue, so they are granted once
	-- per scholar per venue: someone who volunteered elsewhere is still a
	-- newcomer here, and this venue's currency is not one they already hold.
	-- Count only their existing volunteer rows at this venue, before inserting
	-- the new one.
	select count(*) into _existing_count
	from public.volunteers v
	join public.roles r on r.id = v.roleid
	where v.scholarid = _scholarid and r.venueid = _venueid;

	-- Create the volunteer record.
	insert into public.volunteers (scholarid, roleid, active, accepted, expertise, papers)
	values (
		_scholarid, _roleid, _accepted,
		case when _accepted then 'accepted'::public.invited else 'invited'::public.invited end,
		'', _papers
	) returning id into _volunteer_id;

	-- First role at this venue and compensation requested? Settle the welcome
	-- grant in the same transaction, so the volunteer can never exist without it.
	if _existing_count = 0 and _compensate then
		_granted := public._welcome_volunteer(_caller, _scholarid, _roleid, 'Welcome tokens for volunteering');
	end if;

	-- Tell the venue's top-priority role holders -- but only when a scholar volunteered for
	-- THEMSELVES for an OPEN role. That is the news: an admin adding someone is not news to
	-- the admins, and an invitation is answered through accept_role_invite, which stays
	-- deliberately silent because the people who would be told are the ones who sent it.
	--
	-- The predicate is the authorization branch above, reused verbatim rather than restated,
	-- so "may this person volunteer here" and "is this worth telling anyone" cannot drift
	-- apart. It deliberately does not also require _accepted: the interface always passes
	-- true on this path (VolunteerStatus.svelte), and a hand-rolled call passing false makes
	-- a self-invitation that accept_role_invite later resolves without a second notice -- a
	-- dead corner worth accepting to keep one predicate instead of two nearly-identical ones.
	--
	-- Best effort, like delivery itself (see send_email): the volunteer record and its
	-- welcome grant are what must not be lost, and no failure to compose a notice may roll
	-- them back.
	begin
		if _caller = _scholarid and not _invited then
			perform public._notify_new_volunteer(_venueid, _roleid, _scholarid);
		elsif _caller <> _scholarid and _accepted then
			-- The other side of that condition, and the case nobody was told about at all.
			--
			-- An administrator can seat somebody directly, with no invitation to accept. The
			-- notice above is deliberately suppressed for it (it is the admin's own action, so
			-- it is not news to the admins), and RoleInvite only fires where there IS an
			-- invitation -- so the person acquiring a venue commitment, and possibly a welcome
			-- grant with it, was the one party who heard nothing.
			--
			-- Consequential: it is a role with obligations, arriving unasked. No preference is
			-- consulted, for the same reason RoleInvite consults none.
			insert into public.emails (event, scholar, sender, venue, email, subject, message, args)
			select
				'RoleEnrolled', s.id, _caller, _venueid, s.email, null, null,
				to_jsonb(array[
					r.name,
					v.title,
					coalesce(v.slug, v.id::text),
					s.id::text
				])
			from public.scholars s, public.roles r, public.venues v
			where s.id = _scholarid
				and r.id = _roleid
				and v.id = _venueid
				and s.email is not null;
		end if;
	exception when others then
		raise warning 'create_volunteer: volunteer % was created but the venue could not be notified: % (%)',
			_volunteer_id, sqlerrm, sqlstate;
	end;

	-- Return the new volunteer id and what the grant actually came to.
	return jsonb_build_object('volunteer_id', _volunteer_id, 'welcome_granted', _granted);
end;
$function$;

revoke
execute on function public.create_volunteer (uuid, uuid, boolean, boolean, integer)
from
	public;

grant
execute on function public.create_volunteer (uuid, uuid, boolean, boolean, integer) to authenticated;

--------------------------------------
-- Seed
--
-- GENERATED by `node scripts/notification-seeds.js`; src/email/templates.unit.ts asserts this
-- matches the registry. Twenty-two controls now, from one.
insert into public.notification_preferences (key, default_on) values
	('AvailabilityReminder', true),
	('CompensationChanged', true),
	('CompensationRequested', true),
	('ConflictDeclared', false),
	('InviteAccepted', true),
	('NewBid', true),
	('NewVolunteer', true),
	('ProposalSupported', true),
	('SubmissionClaimed', true),
	('SubmissionDone', true),
	('SubmissionsNeedEditors', true),
	('SubmissionsReady', true),
	('ThanksPendingReview', true),
	('ThanksReceived', true),
	('ThanksShared', true),
	('TokensMinted', false),
	('TokensReceived', true),
	('TransactionApproved', true),
	('TransactionsPending', true),
	('VenueApproved', true),
	('VenueDeactivated', true),
	('VolunteerPaused', false)
on conflict (key) do update set default_on = excluded.default_on;

insert into public.optional_emails (event, preference) values
	('AvailabilityReminder', 'AvailabilityReminder'),
	('CompensationChanged', 'CompensationChanged'),
	('CompensationPending', 'CompensationRequested'),
	('CompensationRequested', 'CompensationRequested'),
	('ConflictDeclared', 'ConflictDeclared'),
	('InviteAccepted', 'InviteAccepted'),
	('InviteDeclined', 'InviteAccepted'),
	('NewBid', 'NewBid'),
	('NewVolunteer', 'NewVolunteer'),
	('ProposalDeclined', 'VenueApproved'),
	('ProposalSupported', 'ProposalSupported'),
	('SubmissionClaimed', 'SubmissionClaimed'),
	('SubmissionDone', 'SubmissionDone'),
	('SubmissionNeedsEditor', 'SubmissionsNeedEditors'),
	('SubmissionsNeedEditors', 'SubmissionsNeedEditors'),
	('SubmissionsReady', 'SubmissionsReady'),
	('ThanksPendingReview', 'ThanksPendingReview'),
	('ThanksReceived', 'ThanksReceived'),
	('ThanksShared', 'ThanksShared'),
	('TokensMinted', 'TokensMinted'),
	('TokensReceived', 'TokensReceived'),
	('TransactionApproved', 'TransactionApproved'),
	('TransactionsPending', 'TransactionsPending'),
	('VenueApproved', 'VenueApproved'),
	('VenueDeactivated', 'VenueDeactivated'),
	('VenueReactivated', 'VenueDeactivated'),
	('VolunteerPaused', 'VolunteerPaused'),
	('VolunteerResumed', 'VolunteerPaused')
on conflict (event) do update set preference = excluded.preference;

delete from public.optional_emails where event not in ('AvailabilityReminder', 'CompensationChanged', 'CompensationPending', 'CompensationRequested', 'ConflictDeclared', 'InviteAccepted', 'InviteDeclined', 'NewBid', 'NewVolunteer', 'ProposalDeclined', 'ProposalSupported', 'SubmissionClaimed', 'SubmissionDone', 'SubmissionNeedsEditor', 'SubmissionsNeedEditors', 'SubmissionsReady', 'ThanksPendingReview', 'ThanksReceived', 'ThanksShared', 'TokensMinted', 'TokensReceived', 'TransactionApproved', 'TransactionsPending', 'VenueApproved', 'VenueDeactivated', 'VenueReactivated', 'VolunteerPaused', 'VolunteerResumed');
delete from public.notification_preferences where key not in ('AvailabilityReminder', 'CompensationChanged', 'CompensationRequested', 'ConflictDeclared', 'InviteAccepted', 'NewBid', 'NewVolunteer', 'ProposalSupported', 'SubmissionClaimed', 'SubmissionDone', 'SubmissionsNeedEditors', 'SubmissionsReady', 'ThanksPendingReview', 'ThanksReceived', 'ThanksShared', 'TokensMinted', 'TokensReceived', 'TransactionApproved', 'TransactionsPending', 'VenueApproved', 'VenueDeactivated', 'VolunteerPaused');
