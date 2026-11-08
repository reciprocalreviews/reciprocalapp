-- Call for bids: a venue's editor or admin writes a short personal note to the
-- volunteers of one biddable role, asking them to come and bid.
--
-- Three parts:
--   1. the CallForBids notification preference, seeded from the registry
--   2. public.queue_call_for_bids -- authorize, validate, fan out
--   3. public.call_for_bids_status -- what the compose form needs before sending
--
-- Part 1 has to be a migration rather than a schema-file edit: notification_settings.event
-- carries a foreign key to notification_preferences, so a scholar cannot express an opinion
-- about a notice whose key does not exist yet. The seed block below is GENERATED -- run
-- `node scripts/notification-seeds.js` -- and the same block lives in
-- supabase/schemas/notification_settings.sql. src/email/templates.unit.ts asserts both match
-- the registry, because a stale copy mails people notices they switched off.

--------------------------------------
-- 1. Preference seeds
insert into public.notification_preferences (key, default_on) values
	('AvailabilityReminder', true),
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
	('CallForBids', 'CallForBids'),
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

delete from public.optional_emails where event not in ('AvailabilityReminder', 'CallForBids', 'CompensationChanged', 'CompensationPending', 'CompensationRequested', 'ConflictDeclared', 'InviteAccepted', 'InviteDeclined', 'NewBid', 'NewVolunteer', 'ProposalDeclined', 'ProposalSupported', 'SubmissionClaimed', 'SubmissionDone', 'SubmissionNeedsEditor', 'SubmissionsNeedEditors', 'SubmissionsReady', 'ThanksPendingReview', 'ThanksReceived', 'ThanksShared', 'TokensMinted', 'TokensReceived', 'TransactionApproved', 'TransactionsPending', 'VenueApproved', 'VenueDeactivated', 'VenueReactivated', 'VolunteerPaused', 'VolunteerResumed');
delete from public.notification_preferences where key not in ('AvailabilityReminder', 'CallForBids', 'CompensationChanged', 'CompensationRequested', 'ConflictDeclared', 'InviteAccepted', 'NewBid', 'NewVolunteer', 'ProposalSupported', 'SubmissionClaimed', 'SubmissionDone', 'SubmissionsNeedEditors', 'SubmissionsReady', 'ThanksPendingReview', 'ThanksReceived', 'ThanksShared', 'TokensMinted', 'TokensReceived', 'TransactionApproved', 'TransactionsPending', 'VenueApproved', 'VenueDeactivated', 'VolunteerPaused');

--------------------------------------
-- 2 and 3. The functions

--------------------------------------
-- queue_call_for_bids: a venue's editor writes to the volunteers of one biddable role,
-- asking them to come and bid.
--
-- This is the only mail RR sends that a person composes rather than an event triggers.
-- Everything else in the registry fires on something having already happened; nothing said
-- "we are short of bids and would like you to look", so a program chair's only recourse was
-- to export the volunteer list and mail it from outside RR -- losing the opt-out, the mail
-- log, the delivery tracking and the data download in one step.
--
-- It does NOT break the rule that a caller may not author a body. `_note` becomes ONE
-- template argument: the subject, the attribution, the "why you got this" line and the link
-- are owned by the CallForBids template and rendered at send time, and renderEmail escapes
-- the argument and defangs any URL scheme in it. So a caller chooses what one paragraph says
-- and nothing else -- not the subject, not the recipients, not a link. That is a stricter
-- contract than queue_thanks_emails, the only other template a person writes into, which
-- takes a fully pre-rendered subject and body.
--
-- Unlike queue_email, this authorizes against the venue. queue_email's documented residual is
-- that any authenticated caller may send any template to any scholar id; that is bounded
-- because the caller supplies no prose. Here the caller supplies prose, so the missing check
-- is not affordable and the venue relationship is verified before anything is written.
--
-- Returns {recipients: [{name, email}], venue: title}. The recipients are who was actually
-- reached rather than who was asked for -- a volunteer with no verified address, or one who
-- has silenced this notice, is skipped here and must not be counted in the banner. The title
-- rides along so the interface can label those banners without a second lookup.
create or replace function public.queue_call_for_bids (_role uuid, _note text) returns jsonb language plpgsql security definer
set
	search_path=public,
	pg_temp as $function$
declare
	_caller uuid;
	_venueid uuid;
	_biddable boolean;
	_role_name text;
	_venue_title text;
	_venue_path text;
	_sender_name text;
	_sender_email text;
	_sender_label text;
	_recipients jsonb := '[]'::jsonb;
begin
	_caller := (select auth.uid());
	if _caller is null then
		raise exception 'Authentication required';
	end if;

	-- The role, its venue, and whether bidding is even possible for it. A call for bids sent
	-- to a role the submissions page will not show bid buttons to is a message nobody can act
	-- on, so it is refused here rather than merely hidden in the interface.
	select r.venueid, r.biddable, r.name into _venueid, _biddable, _role_name
	from public.roles r where r.id = _role;
	if _venueid is null then
		raise exception 'Role not found';
	end if;
	if not _biddable then
		raise exception 'Bidding is not enabled for this role';
	end if;

	-- Who may ask. The same union that vets thank-you notes: the venue's admins run it, and
	-- the holders of its priority-0 role are its editors. Note isPriorityZero does not filter
	-- `active` -- it answers a question about authority, and an editor who has paused their
	-- own volunteering is still the venue's editor.
	if not (public.isAdmin(_venueid) or public.isPriorityZero(_venueid)) then
		raise exception 'You are not authorized to write to this venue''s volunteers';
	end if;

	-- The note. Bounded like a thank-you note, and for the same reason: it is one paragraph of
	-- somebody's prose inside branded mail, not a newsletter.
	if _note is null or char_length(btrim(_note)) = 0 then
		raise exception 'A call for bids cannot be empty';
	end if;
	if char_length(_note) > 1000 then
		raise exception 'A call for bids must be at most 1000 characters';
	end if;

	-- The sender must have a verified contact address, because Reply-To is resolved to it
	-- below. This is the one notice whose entire point is that a person is asking; a reply
	-- landing in the steward inbox instead of reaching the editor who wrote it would make the
	-- message a lie about itself. Refusing is better than sending a personal letter nobody can
	-- answer, and the hint lets the interface say why rather than showing a generic failure.
	select coalesce(nullif(btrim(s.name), ''), 'An editor'), s.email
	into _sender_name, _sender_email
	from public.scholars s where s.id = _caller;
	if _sender_email is null then
		raise exception 'A call for bids replies to you, so it needs a verified contact address'
			using hint = 'unverified';
	end if;

	-- The venue's title for the prose and its path for the link -- its web address once it has
	-- one, its id until then; both resolve.
	select v.title, coalesce(v.slug, v.id::text)
	into _venue_title, _venue_path
	from public.venues v where v.id = _venueid;

	-- The sender's own word for their job here. The venue's name for its top role is data, not
	-- a fixed title -- "Editor", "Area Chair", "Associate Editor" -- and is the same reasoning
	-- NewVolunteer applies. An admin who holds no role falls back to the generic word, since
	-- there is no role name to borrow.
	select coalesce(nullif(btrim(r.name), ''), 'an editor') into _sender_label
	from public.roles r
	join public.volunteers v on v.roleid = r.id
	where r.venueid = _venueid and r.priority = 0
		and v.scholarid = _caller and v.accepted = 'accepted'
	order by r.id
	limit 1;
	_sender_label := coalesce(_sender_label, 'an administrator');

	-- N private copies, never one cc'd thread. NewVolunteer uses cc because a welcome should
	-- converge into one conversation; the opposite is true here -- these recipients are
	-- reviewers who must not learn each other's addresses, and a biddable role routinely holds
	-- more than the 50 addresses Resend accepts on a single send.
	--
	-- Skipped: anyone who has stopped volunteering (they said not now), anyone not accepted,
	-- anyone without a verified address, anyone who silenced this notice, and the sender.
	insert into public.emails (event, scholar, sender, venue, email, reply_to, subject, message, args)
	select
		'CallForBids', s.id, _caller, _venueid, s.email, _sender_email,
		-- Null so the body is rendered at send time from the registry, which is the invariant
		-- that keeps prose out of the API.
		null, null,
		-- EVERY element must be non-null: the edge function validates args as
		-- z.array(z.string()), so one JSON null makes the whole body fail to parse, the
		-- function answers 400, and pg_net swallows it -- the mail simply never arrives.
		jsonb_build_array(
			coalesce(nullif(btrim(_venue_title), ''), 'a venue'),
			_sender_name,
			_sender_label,
			btrim(_note),
			coalesce(nullif(btrim(_role_name), ''), 'a volunteer'),
			_venue_path
		)
	from public.volunteers v
	join public.scholars s on s.id = v.scholarid
	where v.roleid = _role
		and v.active
		and v.accepted = 'accepted'
		and s.id <> _caller
		and s.email is not null
		and public.notification_allowed(s.id, 'CallForBids');

	-- The same predicate, because this is what the caller is told it sent.
	select coalesce(jsonb_agg(jsonb_build_object('name', s.name, 'email', s.email)), '[]'::jsonb)
	into _recipients
	from public.volunteers v
	join public.scholars s on s.id = v.scholarid
	where v.roleid = _role
		and v.active
		and v.accepted = 'accepted'
		and s.id <> _caller
		and s.email is not null
		and public.notification_allowed(s.id, 'CallForBids');

	-- The venue title travels back so the interface can render the subject for its "emailed X
	-- about Y" banners without looking it up again and risking a different answer. The mail
	-- itself is rendered at send time from the row; this is display copy only.
	return jsonb_build_object(
		'recipients', _recipients,
		'venue', coalesce(nullif(btrim(_venue_title), ''), 'a venue')
	);
end;
$function$;

alter function public.queue_call_for_bids (uuid, text) OWNER to "postgres";

-- The revoke travels WITH the create or replace, in the same migration: Supabase's default
-- privileges re-grant EXECUTE to anon on every function creation, so a revoke left in an
-- earlier migration is undone by this one.
revoke
execute on function public.queue_call_for_bids (uuid, text)
from
	public,
	anon;

grant
execute on function public.queue_call_for_bids (uuid, text) to authenticated;

--------------------------------------
-- call_for_bids_status: what the compose form needs to know before anything is sent.
--
-- Two things, neither of which the client can work out for itself:
--
-- `eligible` is how many people would actually receive it -- the same predicate the insert
-- above uses. The client can count a role's volunteers, but not which of them have a verified
-- address or have silenced the notice, so a client-side count would promise a number the
-- feedback banners then contradict. DESIGN.md's rule is that a number is reported before
-- submitting so that sending is a decision rather than a discovery.
--
-- `last_sent` / `last_sender` answer "has a colleague already done this?". There is
-- deliberately no rate limit -- an editor decides when their community needs asking -- so this
-- is information in service of that judgment, not a brake on it. It is here rather than read
-- from public.emails directly because that table's SELECT policy admits venue ADMINS only, so
-- a priority-0 editor could not see their own venue's mail log; widening the policy would
-- disclose every notice and address at the venue to a much larger group to answer one
-- question. Scoped like pending_email_verification(), which returns the caller's own row and
-- nothing else.
create or replace function public.call_for_bids_status (_role uuid) returns jsonb language plpgsql security definer
set
	search_path=public,
	pg_temp as $function$
declare
	_venueid uuid;
	_eligible integer;
	_last_sent timestamptz;
	_last_sender text;
begin
	if (select auth.uid()) is null then
		raise exception 'Authentication required';
	end if;

	select r.venueid into _venueid from public.roles r where r.id = _role;
	if _venueid is null then
		raise exception 'Role not found';
	end if;

	if not (public.isAdmin(_venueid) or public.isPriorityZero(_venueid)) then
		raise exception 'You are not authorized to read this venue''s call for bids';
	end if;

	select count(*) into _eligible
	from public.volunteers v
	join public.scholars s on s.id = v.scholarid
	where v.roleid = _role
		and v.active
		and v.accepted = 'accepted'
		and s.id <> (select auth.uid())
		and s.email is not null
		and public.notification_allowed(s.id, 'CallForBids');

	-- Venue-wide rather than per-role: a scholar often volunteers for several of a venue's
	-- roles, so "has this venue asked recently" is the question an editor is actually holding,
	-- and emails carries a venue but not a role.
	select e.time_sent, coalesce(nullif(btrim(s.name), ''), 'Someone')
	into _last_sent, _last_sender
	from public.emails e
	left join public.scholars s on s.id = e.sender
	where e.event = 'CallForBids' and e.venue = _venueid
	order by e.time_sent desc
	limit 1;

	return jsonb_build_object(
		'eligible', _eligible,
		'last_sent', _last_sent,
		'last_sender', _last_sender
	);
end;
$function$;

alter function public.call_for_bids_status (uuid) OWNER to "postgres";

revoke
execute on function public.call_for_bids_status (uuid)
from
	public,
	anon;

grant
execute on function public.call_for_bids_status (uuid) to authenticated;
