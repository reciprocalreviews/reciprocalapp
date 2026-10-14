-- request_compensation also says which tier of recipients it chose -- the role's seated
-- approver, the submission's editors, or the venue's admins -- and the approving role's
-- name, so the email can tell an editor or admin whether a request is theirs to handle or
-- only fell to them because nobody closer to it was seated. Two templates for the fallback
-- tiers join the registry, silenced by the CompensationRequested preference. See
-- supabase/schemas/assignments.sql.
create or replace function public.request_compensation (_venue uuid, _externalid text, _role uuid) returns jsonb language plpgsql security definer
set
	search_path to '' as $$
declare
	_caller uuid;
	_submission uuid;
	_priority integer;
	_a public.assignments;
	_recipients uuid[];
	_title text;
	_role_name text;
	_requester text;
	_tier text;
	_approver_role text;
begin
	_caller := (select auth.uid());
	if _caller is null then
		raise exception 'Authentication required';
	end if;

	select s.id into _submission
	from public.submissions s
	where s.venue = _venue and s.externalid = btrim(coalesce(_externalid, ''));
	if _submission is null then
		raise exception 'No submission with that manuscript ID at this venue'
			using errcode = 'RR020';
	end if;

	select r.priority into _priority
	from public.roles r
	where r.id = _role and r.venueid = _venue;
	if _priority is null then
		raise exception 'That role does not belong to this venue';
	end if;

	select * into _a
	from public.assignments a
	where a.submission = _submission and a.role = _role and a.scholar = _caller
	limit 1
	for update;

	if found then
		if _a.completed then
			raise exception 'This work has already been compensated' using errcode = 'RR021';
		end if;
		if _a.declined_at is not null then
			raise exception 'This request was declined' using errcode = 'RR022';
		end if;
		update public.assignments
		set compensation_requested_at = coalesce(compensation_requested_at, now())
		where id = _a.id;
	else
		if _priority = 0 then
			raise exception 'Editors are compensated by marking a submission done'
				using errcode = 'RR023';
		end if;

		if not exists (
			select 1
			from public.volunteers v
			where v.roleid = _role
				and v.scholarid = _caller
				and v.accepted = 'accepted'
		) then
			raise exception 'Only volunteers in this role can request compensation for it'
				using errcode = 'RR024';
		end if;

		if exists (
			select 1 from public.submissions s
			where s.id = _submission and _caller = any (s.authors)
		) then
			raise exception 'Authors cannot request compensation for their own submission'
				using errcode = 'RR024';
		end if;

		insert into public.assignments (venue, submission, scholar, role, bid, approved, compensation_requested_at)
		values (_venue, _submission, _caller, _role, false, false, now());
	end if;

	-- The scholar seated in the role's approving role on this submission. Which of the three
	-- tiers answered is returned too, so the email can say whether the request is the
	-- recipient's to handle or only fell to them because nobody closer to it was seated.
	_tier := 'approver';
	select coalesce(array_agg(distinct a.scholar), array[]::uuid[]) into _recipients
	from public.assignments a
	join public.roles target on target.id = _role
	where a.submission = _submission and a.approved and a.role = target.approver
		and a.scholar <> _caller
		and not exists (
			select 1 from public.conflicts c
			where c.submissionid = _submission and c.scholarid = a.scholar
		);

	-- Failing that, the submission's editors.
	if cardinality(_recipients) = 0 then
		_tier := 'editors';
		select coalesce(array_agg(distinct a.scholar), array[]::uuid[]) into _recipients
		from public.assignments a
		join public.roles r on r.id = a.role
		where a.submission = _submission and a.approved and r.priority = 0
			and a.scholar <> _caller
			and not exists (
				select 1 from public.conflicts c
				where c.submissionid = _submission and c.scholarid = a.scholar
			);
	end if;

	-- Failing that, the venue's admins.
	if cardinality(_recipients) = 0 then
		_tier := 'admins';
		select coalesce(array_agg(distinct x.scholar), array[]::uuid[]) into _recipients
		from (
			select unnest(v.admins) as scholar
			from public.venues v
			where v.id = _venue
		) x
		where x.scholar <> _caller
			and not exists (
				select 1 from public.conflicts c
				where c.submissionid = _submission and c.scholarid = x.scholar
			);
	end if;

	select s.title into _title from public.submissions s where s.id = _submission;
	select r.name into _role_name from public.roles r where r.id = _role;
	select sc.name into _requester from public.scholars sc where sc.id = _caller;
	select ar.name into _approver_role
	from public.roles r
	join public.roles ar on ar.id = r.approver
	where r.id = _role;

	return jsonb_build_object(
		'submission', _submission,
		'recipients', to_jsonb(_recipients),
		'title', _title,
		'role', _role_name,
		'requester', _requester,
		'tier', _tier,
		'approver_role', _approver_role
	);
end;
$$;

alter function public.request_compensation (uuid, text, uuid) OWNER to "postgres";

revoke
execute on function public.request_compensation (uuid, text, uuid)
from
	public,
	anon;

grant
execute on function public.request_compensation (uuid, text, uuid) to authenticated;

-- GENERATED by `node scripts/notification-seeds.js`: the registry's two new fallback-tier
-- templates defer to the CompensationRequested preference.
insert into public.notification_preferences (key, default_on) values
	('AvailabilityReminder', true),
	('BiddingDigest', true),
	('CallForBids', true),
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
	('BiddingDigest', 'BiddingDigest'),
	('CallForBids', 'CallForBids'),
	('CompensationChanged', 'CompensationChanged'),
	('CompensationPending', 'CompensationRequested'),
	('CompensationRequested', 'CompensationRequested'),
	('CompensationRequestedToAdmins', 'CompensationRequested'),
	('CompensationRequestedToEditors', 'CompensationRequested'),
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

delete from public.optional_emails where event not in ('AvailabilityReminder', 'BiddingDigest', 'CallForBids', 'CompensationChanged', 'CompensationPending', 'CompensationRequested', 'CompensationRequestedToAdmins', 'CompensationRequestedToEditors', 'ConflictDeclared', 'InviteAccepted', 'InviteDeclined', 'NewBid', 'NewVolunteer', 'ProposalDeclined', 'ProposalSupported', 'SubmissionClaimed', 'SubmissionDone', 'SubmissionNeedsEditor', 'SubmissionsNeedEditors', 'SubmissionsReady', 'ThanksPendingReview', 'ThanksReceived', 'ThanksShared', 'TokensMinted', 'TokensReceived', 'TransactionApproved', 'TransactionsPending', 'VenueApproved', 'VenueDeactivated', 'VenueReactivated', 'VolunteerPaused', 'VolunteerResumed');
delete from public.notification_preferences where key not in ('AvailabilityReminder', 'BiddingDigest', 'CallForBids', 'CompensationChanged', 'CompensationRequested', 'ConflictDeclared', 'InviteAccepted', 'NewBid', 'NewVolunteer', 'ProposalSupported', 'SubmissionClaimed', 'SubmissionDone', 'SubmissionsNeedEditors', 'SubmissionsReady', 'ThanksPendingReview', 'ThanksReceived', 'ThanksShared', 'TokensMinted', 'TokensReceived', 'TransactionApproved', 'TransactionsPending', 'VenueApproved', 'VenueDeactivated', 'VolunteerPaused');
