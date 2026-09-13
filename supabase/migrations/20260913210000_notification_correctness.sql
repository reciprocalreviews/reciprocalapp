-- Correctness: four places where the same act notified on one path and not another.
--
--   * A transaction being APPROVED now tells its proposer, as declining always has. Half a
--     decision explaining itself and the other half saying nothing is not a policy about
--     which mail matters; it is an omission that had gone unnoticed because the quiet half
--     is the happy one.
--   * A venue proposal being DECLINED now tells the supporters and listed editors who were
--     emailed when it was created. VenueApproved had no counterpart at all, so the people
--     told a venue was being proposed for their community were left to infer the ending.
--   * A thank-you note being SHARED now tells its author, as declining one always has.
--   * A contact email being CHANGED now tells the address being replaced -- the only party
--     with no other way to notice, since it simply goes quiet.
--
-- The first three are silenceable and appear in the seed below. EmailChanged is not: an
-- account's contact address changing without its previous owner hearing is the shape of a
-- takeover going unnoticed, and there is no version of that worth offering as a checkbox.

--------------------------------------
-- decline_venue_proposal: mail the people a proposal was announced to, and close it, in one
-- transaction. See the schema file for why this cannot be an email followed by a delete.

create or replace function public.decline_venue_proposal (
	_proposal_id uuid,
	_subject text,
	_message text
) returns integer language plpgsql security definer
set
	"search_path" to 'public',
	'pg_temp' as $function$
declare
	_caller uuid := (select auth.uid());
	_proposal public.proposals;
	_supporters integer;
	_editors integer;
begin
	if _caller is null then
		raise exception 'Authentication required';
	end if;
	if not public.isSteward() then
		raise exception 'Only stewards can decline venue proposals';
	end if;

	select * into _proposal from public.proposals where id = _proposal_id;
	if not found then
		raise exception 'Proposal not found';
	end if;

	-- The supporters, who are scholars and so have a preference to honour.
	insert into public.emails (event, scholar, sender, venue, email, subject, message)
	select 'ProposalDeclined', s.id, _caller, null, s.email, _subject, _message
	from public.supporters p
	join public.scholars s on s.id = p.scholarid
	where p.proposalid = _proposal_id
		and s.email is not null
		and public.notification_allowed(s.id, 'ProposalDeclined');

	get diagnostics _supporters = row_count;

	-- The listed editors, who are addresses rather than accounts. No preference applies:
	-- there is no scholar to hold one, which is the same reason ProposalCreatedEditors is
	-- sent to them unconditionally. Anyone listed who also supported is skipped, so a person
	-- who is both does not get two copies.
	insert into public.emails (event, scholar, sender, venue, email, subject, message)
	select 'ProposalDeclined', null, _caller, null, e, _subject, _message
	from unnest(_proposal.editors) as e
	where e is not null
		and e <> ''
		and e not in (
			select s.email from public.supporters p
			join public.scholars s on s.id = p.scholarid
			where p.proposalid = _proposal_id and s.email is not null
		);

	-- Two counters rather than one: GET DIAGNOSTICS assigns an item to a variable and takes
	-- no expression, so `_count = _count + row_count` is a syntax error rather than a sum.
	get diagnostics _editors = row_count;

	delete from public.proposals where id = _proposal_id;

	return _supporters + _editors;
end;
$function$;

alter function public.decline_venue_proposal (uuid, text, text) OWNER to "postgres";

-- Explicitly revoked, not merely un-granted: Supabase's ALTER DEFAULT PRIVILEGES hands anon
-- EXECUTE on every function created in `public` at creation time.
revoke
execute on function public.decline_venue_proposal (uuid, text, text)
from
	public,
	anon;

grant
execute on function public.decline_venue_proposal (uuid, text, text) to authenticated;

--------------------------------------
-- queue_thanks_emails gains an 'author_shared' audience. A new audience rather than a
-- parameter naming the event: the event being fixed per audience is what stops this function
-- becoming a way to send any template to anyone.

create or replace function public.queue_thanks_emails (
	_thanks_id uuid,
	_audience text,
	_subject text,
	_message text
) returns integer language plpgsql security definer
set
	search_path=public,
	pg_temp as $function$
declare
	_caller uuid;
	_t public.thanks;
	_vet boolean;
	_count integer;
begin
	_caller := (select auth.uid());
	if _caller is null then
		raise exception 'Authentication required';
	end if;

	select * into _t from public.thanks where id = _thanks_id;
	if not found then
		raise exception 'Thank-you note not found';
	end if;
	select vet_thanks into _vet from public.venues where id = _t.venue;

	if _audience = 'recipients' then
		if _t.status <> 'approved' then
			raise exception 'Only an approved note can be delivered';
		end if;
		if not (
			public.isAdmin(_t.venue)
			or public.isPriorityZero(_t.venue)
			or (not _vet and _caller = _t.author)
		) then
			raise exception 'You are not authorized to deliver this note';
		end if;
		insert into public.emails (event, scholar, sender, venue, email, subject, message)
		select 'ThanksReceived', s.id, null, _t.venue, s.email, _subject, _message
		from (
			select distinct a.scholar
			from public.assignments a
			where a.submission = _t.submission and a.approved = true and a.scholar <> _t.author
		) r
		join public.scholars s on s.id = r.scholar
		where s.email is not null and public.notification_allowed(s.id, 'ThanksReceived');

	elsif _audience = 'vetters' then
		if _caller <> _t.author then
			raise exception 'You are not authorized to notify vetters';
		end if;
		insert into public.emails (event, scholar, sender, venue, email, subject, message)
		select 'ThanksPendingReview', s.id, null, _t.venue, s.email, _subject, _message
		from (
			select unnest(admins) as scholar from public.venues where id = _t.venue
			union
			select v.scholarid
			from public.volunteers v
			join public.roles r on r.id = v.roleid
			where r.venueid = _t.venue and r.priority = 0 and v.accepted = 'accepted'
		) vt
		join public.scholars s on s.id = vt.scholar
		where s.email is not null and s.id <> _caller
			and public.notification_allowed(s.id, 'ThanksPendingReview');

	-- The author's copy of the GOOD outcome. A separate audience rather than a parameter for
	-- the event, because the event being fixed per audience is what keeps this function from
	-- becoming a way to send any template to anyone: the caller picks an audience from a closed
	-- set, and the function decides both who is written to and what it says it is.
	elsif _audience = 'author_shared' then
		if not (public.isAdmin(_t.venue) or public.isPriorityZero(_t.venue)) then
			raise exception 'You are not authorized to notify the author';
		end if;
		insert into public.emails (event, scholar, sender, venue, email, subject, message)
		select 'ThanksShared', s.id, null, _t.venue, s.email, _subject, _message
		from public.scholars s
		where s.id = _t.author and s.email is not null
			and public.notification_allowed(s.id, 'ThanksShared');

	elsif _audience = 'author' then
		if not (public.isAdmin(_t.venue) or public.isPriorityZero(_t.venue)) then
			raise exception 'You are not authorized to notify the author';
		end if;
		insert into public.emails (event, scholar, sender, venue, email, subject, message)
		select 'ThanksDeclined', s.id, null, _t.venue, s.email, _subject, _message
		from public.scholars s
		where s.id = _t.author and s.email is not null
			and public.notification_allowed(s.id, 'ThanksDeclined');

	else
		raise exception 'Unknown thanks email audience';
	end if;

	get diagnostics _count = row_count;
	return _count;
end;
$function$;

revoke
execute on function public.queue_thanks_emails (uuid, text, text, text)
from
	public;

grant
execute on function public.queue_thanks_emails (uuid, text, text, text) to authenticated;

--------------------------------------
-- verify_email captures the address it is about to overwrite, and writes to it.

create or replace function public.verify_email (_token text) RETURNS jsonb LANGUAGE "plpgsql" SECURITY DEFINER
set
	"search_path" to 'public',
	'pg_temp' as $$
declare
	_row public.email_verifications%rowtype;
	_previous text;
begin
	select * into _row from public.email_verifications
	where token_hash = encode(extensions.digest(_token, 'sha256'), 'hex');

	if not found then
		return jsonb_build_object('status', 'invalid');
	end if;

	-- Already confirmed: say so, whatever the clock says. This branch comes FIRST
	-- deliberately, and it is new. Verification has always been idempotent so that an email
	-- scanner's prefetch cannot burn the link, but the row used to be deleted on expiry, so
	-- "verified, then expired" was unreachable. Now that the row survives, a scholar who
	-- verified an hour after the link was sent and reopened the same message two days later
	-- would be told it had expired — which is false, and which would send them to a resend
	-- button for an address that is already theirs.
	if _row.verified_at is not null then
		return jsonb_build_object(
			'status', 'verified',
			'scholar', _row.scholar,
			'email', _row.candidate_email
		);
	end if;

	-- Expired, and the row is KEPT where it used to be deleted. Deleting it threw away the
	-- only evidence the scholar had asked for anything, so the only thing the interface
	-- could offer was a blank form. Keeping it costs one row per scholar — `scholar` is the
	-- primary key, so a later request replaces this one rather than adding to it, and the
	-- table cannot grow past the number of scholars — and it leaks nothing: the candidate is
	-- an address the scholar typed into their own profile, the token is stored as a hash,
	-- and that hash is now useless. Erasure still removes the row (erasures.sql).
	if _row.expires_at < now() then
		return jsonb_build_object('status', 'expired');
	end if;

	-- Idempotent commit: still no delete, so a repeat fetch within the validity window
	-- (email link scanner prefetch, or SvelteKit hover-preload) returns 'verified' rather
	-- than a misleading 'invalid'. A later request replaces this row (upsert on the
	-- scholar PK).
	select email into _previous from public.scholars where id = _row.scholar;

	update public.scholars set email = _row.candidate_email where id = _row.scholar;

	-- Tell the address that just stopped receiving this scholar's mail.
	--
	-- It is the only party with no other way to find out: the new address gets everything from
	-- here on, the scholar sees their profile, and the old address simply goes quiet -- which
	-- is indistinguishable from a takeover. Consequential, so no preference is consulted.
	--
	-- Safe to put after the early return above: a repeat fetch inside the validity window
	-- exits at `verified_at is not null` and never reaches here, so the notice is sent once.
	-- Nothing is sent on a first-ever verification (_previous is null) or a re-verification of
	-- the same address.
	if _previous is not null and _previous <> _row.candidate_email then
		insert into public.emails (event, scholar, sender, venue, email, subject, message, args)
		values (
			'EmailChanged', _row.scholar, null, null, _previous, null, null,
			to_jsonb(array[_row.candidate_email])
		);
	end if;

	-- Stamped rather than deleted, so pending_email_verification() can tell a confirmed row
	-- from one still waiting. coalesce keeps the FIRST confirmation time under a re-fetch.
	update public.email_verifications
	set verified_at = coalesce(verified_at, now())
	where scholar = _row.scholar;

	return jsonb_build_object(
		'status', 'verified',
		'scholar', _row.scholar,
		'email', _row.candidate_email
	);
end;
$$;

alter function public.verify_email (text) OWNER to "postgres";

revoke
execute on function public.verify_email (text)
from
	public;

grant
execute on function public.verify_email (text) to anon,
authenticated;

--------------------------------------
-- Seed
--
-- GENERATED by `node scripts/notification-seeds.js`; src/email/templates.unit.ts asserts this
-- matches the registry.
insert into public.notification_preferences (key, default_on) values
	('CompensationRequested', true),
	('NewVolunteer', true),
	('SubmissionsNeedEditors', true),
	('ThanksPendingReview', true),
	('ThanksReceived', true),
	('ThanksShared', true),
	('TransactionApproved', true),
	('VenueApproved', true)
on conflict (key) do update set default_on = excluded.default_on;

insert into public.optional_emails (event, preference) values
	('CompensationRequested', 'CompensationRequested'),
	('NewVolunteer', 'NewVolunteer'),
	('ProposalDeclined', 'VenueApproved'),
	('SubmissionNeedsEditor', 'SubmissionsNeedEditors'),
	('SubmissionsNeedEditors', 'SubmissionsNeedEditors'),
	('ThanksPendingReview', 'ThanksPendingReview'),
	('ThanksReceived', 'ThanksReceived'),
	('ThanksShared', 'ThanksShared'),
	('TransactionApproved', 'TransactionApproved'),
	('VenueApproved', 'VenueApproved')
on conflict (event) do update set preference = excluded.preference;

delete from public.optional_emails where event not in ('CompensationRequested', 'NewVolunteer', 'ProposalDeclined', 'SubmissionNeedsEditor', 'SubmissionsNeedEditors', 'ThanksPendingReview', 'ThanksReceived', 'ThanksShared', 'TransactionApproved', 'VenueApproved');
delete from public.notification_preferences where key not in ('CompensationRequested', 'NewVolunteer', 'SubmissionsNeedEditors', 'ThanksPendingReview', 'ThanksReceived', 'ThanksShared', 'TransactionApproved', 'VenueApproved');
