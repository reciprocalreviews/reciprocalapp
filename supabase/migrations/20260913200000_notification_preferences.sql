-- Notification preferences for more than one notice.
--
-- The scholar profile showed exactly one checkbox. That was the correct output of a system in
-- which exactly one of 22 templates carried `optional: true` -- the machinery to offer more
-- was already there. What was missing was anything to ENFORCE a preference: the registry
-- declared that "the producer of an optional email is responsible for checking that table
-- before queuing it", and exactly one producer ever did. Marking a second template optional
-- would have rendered a checkbox that silenced nothing.
--
-- This migration moves that responsibility into the database, and adds the two things a
-- registry-wide answer needs that a single hand-written check did not: a way for a reminder
-- to share the control of the notice it chases, and a per-preference default, so that two
-- dozen notices do not arrive at once for everyone who has never opened their profile.
--
-- Both tables are GENERATED from supabase/functions/_shared/templates.ts by
-- `node scripts/notification-seeds.js`; src/email/templates.unit.ts asserts they match.

create table if not exists public.notification_preferences (
	-- The preference key. A template key marked `optional` in the registry; the templates that
	-- defer to it via `silencedBy` are listed in public.optional_emails below.
	key text not null,
	-- Whether this preference is on for a scholar with no row in notification_settings.
	--
	-- "Absence is the default, and the default is on" was a fine rule for one notice and a bad
	-- one for two dozen: it would opt every existing scholar into every new notice at once.
	-- The default moved here rather than being backfilled as rows so that adding a preference
	-- is still nothing but a mark on a template.
	default_on boolean not null default true
);

alter table public.notification_preferences OWNER to "postgres";

alter table only public.notification_preferences
add constraint "notification_preferences_pkey" primary key (key);

-- Every silenceable template, mapped to the preference that governs it. A template with no
-- row here is consequential and always sends -- so an accidental omission fails safe, toward
-- delivering mail rather than toward swallowing it.
create table if not exists public.optional_emails (
	-- The template key, as public.emails.event holds it.
	event text not null,
	-- The preference governing it. Equal to `event` for a template that owns its key, and the
	-- target of `silencedBy` for one that defers -- a reminder, or the plural of a notice.
	preference text not null
);

alter table public.optional_emails OWNER to "postgres";

alter table only public.optional_emails
add constraint "optional_emails_pkey" primary key (event);

alter table only public.optional_emails
add constraint "optional_emails_preference_fkey" foreign KEY (preference) references public.notification_preferences (key) on delete cascade;

alter table public.notification_preferences enable row level security;

alter table public.optional_emails enable row level security;

-- Explicitly revoked, not merely un-granted: Supabase's ALTER DEFAULT PRIVILEGES hands anon
-- and authenticated rights on every table created in `public` at creation time.
revoke all on table public.notification_preferences from public, anon, authenticated;

revoke all on table public.optional_emails from public, anon, authenticated;

grant select on table public.notification_preferences to service_role;

grant select on table public.optional_emails to service_role;

create or replace function public.notification_allowed (_scholar uuid, _event text) returns boolean language sql stable security definer
set
	"search_path" to 'public',
	'pg_temp' as $$
select
	not exists (
		select 1
		from public.optional_emails o
		join public.notification_preferences p on p.key = o.preference
		left join public.notification_settings n on n.scholar = _scholar
		and n.event = o.preference
		where o.event = _event
			and not coalesce(n.enabled, p.default_on)
	);
$$;

alter function public.notification_allowed (uuid, text) OWNER to "postgres";

-- Explicitly revoked, not merely un-granted: Supabase's ALTER DEFAULT PRIVILEGES hands anon
-- and authenticated EXECUTE on every function created in `public` at creation time, and
-- `revoke ... from public` does not take those back. See 20260831000000. This one reads
-- tables that are deny-all to clients, so leaving it open would publish whose mute list says
-- what, one probe at a time.
revoke
execute on function public.notification_allowed (uuid, text)
from
	public,
	anon,
	authenticated;

grant
execute on function public.notification_allowed (uuid, text) to service_role;

insert into public.notification_preferences (key, default_on) values
	('CompensationRequested', true),
	('NewVolunteer', true),
	('SubmissionsNeedEditors', true),
	('ThanksPendingReview', true),
	('ThanksReceived', true),
	('VenueApproved', true)
on conflict (key) do update set default_on = excluded.default_on;

insert into public.optional_emails (event, preference) values
	('CompensationRequested', 'CompensationRequested'),
	('NewVolunteer', 'NewVolunteer'),
	('SubmissionNeedsEditor', 'SubmissionsNeedEditors'),
	('SubmissionsNeedEditors', 'SubmissionsNeedEditors'),
	('ThanksPendingReview', 'ThanksPendingReview'),
	('ThanksReceived', 'ThanksReceived'),
	('VenueApproved', 'VenueApproved')
on conflict (event) do update set preference = excluded.preference;

delete from public.optional_emails where event not in ('CompensationRequested', 'NewVolunteer', 'SubmissionNeedsEditor', 'SubmissionsNeedEditors', 'ThanksPendingReview', 'ThanksReceived', 'VenueApproved');
delete from public.notification_preferences where key not in ('CompensationRequested', 'NewVolunteer', 'SubmissionsNeedEditors', 'ThanksPendingReview', 'ThanksReceived', 'VenueApproved');

-- Constrain notification_settings.event to keys that are actually silenceable.
--
-- The column was deliberately unconstrained, on the reasoning that "an unrecognized key is
-- simply inert, because nothing reads it". public.notification_allowed now reads it, and the
-- table's write policies carry no column boundary (deliberately -- see the schema file), so
-- without this any scholar could insert ('me', 'SubmissionCharged', false) and switch off the
-- notice that they had been billed. DESIGN.md makes being told you were charged an
-- accountability property rather than a preference.
--
-- Rows naming a key that is not silenceable are deleted first. Today that can only be a
-- 'NewVolunteer' row, which survives. The delete is here because the constraint cannot be
-- added over a row that violates it, and a deployment failing on somebody's stray preference
-- would be a bad way to discover one.
delete from public.notification_settings
where event not in (select key from public.notification_preferences);

alter table only public.notification_settings
drop constraint if exists notification_settings_event_fkey;

alter table only public.notification_settings
add constraint notification_settings_event_fkey foreign key (event) references public.notification_preferences (key) on delete cascade;

-- Consult the preference when resolving recipients. The predicate goes in BOTH queries: the
-- second builds the list the caller is told it mailed, and reporting the unfiltered one
-- would have the interface announce "emailed 4 people" for a notice that reached one.
create or replace function public.queue_email (
	_event text,
	_args text[] default '{}',
	_scholars uuid[] default null,
	_proposal uuid default null
) returns jsonb language plpgsql security definer
set
	"search_path" to 'public',
	'pg_temp' as $$
declare
	_caller uuid := (select auth.uid());
	_recipients jsonb := '[]'::jsonb;
begin
	if _caller is null then
		raise exception 'Authentication required';
	end if;
	if _event is null or _event = '' then
		raise exception 'An event is required';
	end if;
	-- VerifyEmail is the one template that renders an ARGUMENT as a clickable link
	-- (templates.ts `urlArgs`), so allowing it here would let a caller send branded mail
	-- containing a link of their choosing. It is queued only by
	-- public.request_email_verification, which builds the URL itself.
	if _event = 'VerifyEmail' then
		raise exception 'VerifyEmail is queued only by request_email_verification';
	end if;

	-- Resolve scholar recipients. Scholars with no verified contact email are skipped:
	-- scholars.email holds only verified addresses, so a null here means "not verified".
	--
	-- Silenced scholars are skipped too. This is the whole of the opt-out mechanism: the
	-- registry used to say each producer was responsible for consulting
	-- public.notification_settings itself, and exactly one of them ever did, which is why the
	-- profile could only ever offer one checkbox. Resolving it here means marking a template
	-- `optional` is genuinely all it takes.
	--
	-- A template with no public.optional_emails row is consequential, matches nothing here,
	-- and always sends -- so a template missing from the seed fails toward delivering mail.
	if _scholars is not null then
		insert into public.emails (event, scholar, sender, venue, email, subject, message, args)
		select _event, s.id, _caller, null, s.email, null, null, to_jsonb(_args)
		from public.scholars s
		where s.id = any(_scholars) and s.email is not null
			and public.notification_allowed(s.id, _event);

		-- The same predicate, because this is what the caller is told it sent. Reporting the
		-- unfiltered list would have the application announce "emailed 4 people" for a notice
		-- that reached one, and those counts surface to users as feedback banners.
		select coalesce(jsonb_agg(jsonb_build_object('name', s.name, 'email', s.email)), '[]'::jsonb)
		into _recipients
		from public.scholars s
		where s.id = any(_scholars) and s.email is not null
			and public.notification_allowed(s.id, _event);
	end if;

	-- Resolve a proposal's editor addresses.
	if _proposal is not null then
		insert into public.emails (event, scholar, sender, venue, email, subject, message, args)
		select _event, null, _caller, null, e, null, null, to_jsonb(_args)
		from public.proposals p, unnest(p.editors) as e
		where p.id = _proposal and e is not null and e <> '';

		select _recipients || coalesce(jsonb_agg(jsonb_build_object('name', e, 'email', e)), '[]'::jsonb)
		into _recipients
		from public.proposals p, unnest(p.editors) as e
		where p.id = _proposal and e is not null and e <> '';
	end if;

	return _recipients;
end;
$$;

alter function public.queue_email (text, text[], uuid[], uuid) OWNER to "postgres";

-- Travels with the CREATE OR REPLACE, not in a later migration: Supabase's ALTER DEFAULT
-- PRIVILEGES re-opens EXECUTE to anon on every re-creation, so a redefinition that does not
-- carry its own revoke silently reopens the function. definer_grants.sql check 1 catches it;
-- `supabase db diff` does not.
revoke
execute on function public.queue_email (text, text[], uuid[], uuid)
from
	public,
	anon;

grant
execute on function public.queue_email (text, text[], uuid[], uuid) to authenticated;

--------------------------------------
-- The other two producers that resolve recipients themselves.
--
-- Neither goes through public.queue_email: queue_thanks_emails resolves reviewers server-side
-- to keep them anonymous from the author, and _notify_new_volunteer builds a single shared
-- thread with a Cc list and a Reply-To. Both must therefore consult the preference themselves
-- -- which is the per-producer contract this migration exists to stop relying on, so they
-- call the same predicate rather than writing the check out a third and fourth time.
--
-- _notify_new_volunteer previously inlined that check against notification_settings. Folding
-- it onto public.notification_allowed is what makes 'NewVolunteer' honour default_on like
-- every other preference, rather than remaining the one key with its own hand-written rule.

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


create or replace function public._notify_new_volunteer (_venueid uuid, _roleid uuid, _scholarid uuid) returns integer language plpgsql security definer
set
	search_path=public,
	pg_temp as $function$
declare
	_top_role uuid;
	_top_role_name text;
	_ids uuid[];
	_addrs text[];
	_reply_to text;
	_name text;
	_venue_title text;
	_venue_path text;
	_role_name text;
begin
	-- The venue's top-priority role -- whatever this venue calls it. The name is data, so it
	-- is read here and handed to the template rather than assumed to be "Editor".
	-- `order by r.id limit 1` mirrors create_submission: priority is unique per venue by
	-- construction (create_role assigns max+1, and 20260828030000 renumbered the existing
	-- ones densely), and this stays deterministic if it ever isn't. Resolving a single role
	-- id also means a scholar who somehow holds two priority-0 roles is addressed once.
	select r.id, r.name into _top_role, _top_role_name
	from public.roles r
	where r.venueid = _venueid and r.priority = 0
	order by r.id
	limit 1;

	if _top_role is null then
		return 0;
	end if;

	-- The new volunteer. scholars.email holds only VERIFIED addresses, so null here means
	-- there is no reply path. The notice still goes out: the news is what matters, and a
	-- scholar with no contact address is precisely the one an editor needs the profile link
	-- for. The null is also what makes the branded footer fall back to naming the stewards
	-- instead of promising that a reply reaches a person.
	select coalesce(nullif(btrim(s.name), ''), 'A scholar'), s.email
	into _name, _reply_to
	from public.scholars s
	where s.id = _scholarid;

	-- The venue's title for the prose and its path for the link. The path is the venue's web
	-- address once it has chosen one, and its id until then; both resolve, so a venue that
	-- has not named itself still gets a working link.
	select v.title, coalesce(v.slug, v.id::text)
	into _venue_title, _venue_path
	from public.venues v
	where v.id = _venueid;
	select r.name into _role_name from public.roles r where r.id = _roleid;

	-- Who hears about it: ACTIVE, ACCEPTED holders of that role, with a verified contact
	-- address, who have not silenced this notice, and never the new volunteer themselves --
	-- someone can hold the top role here and still volunteer for another open one, and
	-- telling them their own news is noise.
	--
	-- Note this filters `active`, which public.isPriorityZero() does not. The app's own
	-- convention is the one followed here (see emailEditorsOf in SupabaseCRUD, which filters
	-- active and accepted): someone who has stopped volunteering should not be mailed about
	-- the venue's newcomers. Left as a comment rather than "fixed" in isPriorityZero,
	-- because that function answers a question about authority and this one answers a
	-- question about mail, and they are not obliged to agree.
	--
	-- Ordered by how long they have held the role, id breaking ties, so the To slot is
	-- deterministic and the venue's longest-standing holder is the one addressed. The
	-- tiebreak is load-bearing rather than decorative: supabase/seed.sql gives many
	-- volunteer rows an identical created_at to the microsecond, so ordering by it alone is
	-- genuinely ambiguous.
	select array_agg(s.id order by v.created_at, s.id),
	       array_agg(s.email order by v.created_at, s.id)
	into _ids, _addrs
	from public.volunteers v
	join public.scholars s on s.id = v.scholarid
	where v.roleid = _top_role
		and v.active
		and v.accepted = 'accepted'
		and s.id <> _scholarid
		and s.email is not null
		and public.notification_allowed(s.id, 'NewVolunteer');

	-- Nobody reachable. Saying nothing is right: the volunteering succeeded, and a venue
	-- whose top-role holders have no verified address is a venue configuration problem
	-- rather than a failure of volunteering. Note this is the DEFAULT state of a freshly
	-- approved venue, whose admins have not necessarily verified an address yet.
	if _addrs is null or cardinality(_addrs) = 0 then
		return 0;
	end if;

	-- Resend caps a message at 50 addresses across to + cc + bcc and rejects the whole send
	-- past that -- a rejection pg_net swallows, so the notice would vanish rather than fail
	-- loudly. No real venue has 50 people in its top role; this slice is what keeps that
	-- true rather than merely likely.
	if cardinality(_addrs) > 50 then
		_ids := _ids[1:50];
		_addrs := _addrs[1:50];
	end if;

	-- ONE row, one send, one thread: the first holder in To, the rest in Cc. Reply reaches
	-- the volunteer; Reply All reaches the volunteer and every other holder. A row per
	-- recipient would mean each of them receiving one copy addressed to them plus N-1 as a
	-- Cc, and the replies never converging.
	insert into public.emails (
		event, scholar, sender, venue, email, cc, reply_to, subject, message, args
	) values (
		'NewVolunteer',
		_ids[1],
		-- Attribution, as queue_email records its caller. This makes the row readable by the
		-- volunteer through the SELECT policy's `sender` branch, which leaks nothing:
		-- scholars.email is already readable by anyone signed in. thanks.sql nulls its
		-- sender because reviewer anonymity depends on it; nothing here is anonymous -- the
		-- volunteer is named in the body.
		_scholarid,
		_venueid,
		_addrs[1],
		-- nullif so a lone holder yields NULL rather than the empty array the check
		-- constraint in part 1 forbids.
		nullif(_addrs[2:], '{}'::text[]),
		_reply_to,
		-- Null so the body is rendered at send time from the template registry, which is the
		-- invariant that keeps prose out of the API.
		null,
		null,
		-- EVERY element must be non-null. jsonb_build_array with a NULL yields JSON null;
		-- the edge function validates args as z.array(z.string()), so one null makes the
		-- WHOLE body fail to parse, the function answers 400, and pg_net swallows it -- the
		-- email simply never arrives, with nothing on screen to say so. scholars.name is
		-- nullable (a fresh ORCID account has none) and role and venue titles default to '',
		-- so every one of them is coalesced.
		jsonb_build_array(
			_name,
			coalesce(nullif(btrim(_role_name), ''), 'volunteer'),
			coalesce(nullif(btrim(_venue_title), ''), 'a venue'),
			_scholarid::text,
			_venue_path,
			coalesce(nullif(btrim(_top_role_name), ''), 'top')
		)
	);

	return cardinality(_addrs);
end;
$function$;

alter function public._notify_new_volunteer (uuid, uuid, uuid) OWNER to "postgres";

revoke
execute on function public._notify_new_volunteer (uuid, uuid, uuid)
from
	public,
	anon,
	authenticated;
