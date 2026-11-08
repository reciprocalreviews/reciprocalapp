-- A scholar volunteered and nobody was told.
--
-- create_volunteer wrote the volunteer row, settled the welcome grant, and stopped. The
-- venue found out when someone happened to open its volunteers list. This is the same gap
-- 20260828040000 closed at the other end of the venue's work -- a submission arriving and
-- reaching nobody -- applied to the moment a community gains a member. A newcomer who
-- volunteers and hears nothing has no signal that anyone noticed, and the venue loses the
-- cheapest thing it can do, which is say hello.
--
-- The notice goes to the venue's priority-0 role holders, and two properties of it are the
-- reason this migration is as large as it is:
--
--   1. Its Reply-To is the NEW VOLUNTEER's address, so an editor hits Reply and welcomes
--      them rather than filing a support request with the stewards.
--   2. Every other holder of that role is Cc'd, so the welcome is one shared thread rather
--      than N private ones that never see each other.
--
-- The emails pipeline could express neither. It had one recipient column and a Reply-To
-- hardcoded to the steward inbox in the `resend` edge function. Both are added here, and
-- both are recipient surface, so the rule that keeps the pipeline from being an open relay
-- gets STRICTER rather than looser: neither column may ever be written from a value that
-- crossed the API. queue_email and queue_steward_email gain no parameters for either; the
-- only writer is the SECURITY DEFINER function in part 4, which resolves every address
-- from scholars.email.
--
-- Two consequences turned up that are easy to miss, and both are handled in part 7: an
-- address in `cc` or `reply_to` is matched by neither branch of forget_scholar's scrub, so
-- an erased scholar's address would have survived indefinitely; and export_scholar_data
-- keys "mail I received" on `scholar` alone, so a Cc'd recipient's own export would have
-- omitted mail they actually got.
--
-- Finally: the priority-0 role's NAME is venue data. A venue calls it "Editor", "Area
-- Chair", "Associate Editor", or something else entirely, so the name is read from the row
-- and passed to the template rather than written into the prose.

--------------------------------------
-- 1. emails learns a Cc list and a per-message Reply-To.
alter table public.emails
add column if not exists cc text[];

alter table public.emails
add column if not exists reply_to text;

comment on column public.emails.cc is 'The rest of this message''s recipients, when it is meant to be ONE shared thread rather than N private copies. Null for the vast majority of mail, which has a single recipient. Resolved server-side from scholars.email, never accepted from a caller.';

comment on column public.emails.reply_to is 'Where a reply to this message should go, when that is not the steward inbox. Null means stewards@, which is what every message sent before this column existed carried. Resolved server-side, never accepted from a caller: it points replies at an address, so a caller-supplied value would be a redirect inside genuinely branded mail.';

-- An empty array is not "no Cc": it is a list someone built and then emptied, and it would
-- travel to Resend as `cc: []`, which that API treats as a malformed field rather than an
-- absent one. Normalizing at the source makes `cc is null` the single unambiguous
-- "one recipient" test, so the trigger and the edge function never have to guess.
alter table public.emails
drop constraint if exists emails_cc_shape;

alter table public.emails
add constraint emails_cc_shape check (
	cc is null
	or (
		cardinality(cc)>0
		and array_position(cc, null::text) is null
	)
);

--------------------------------------
-- 2. send_email carries them to the edge function.
--
-- The body below is an explicit whitelist: a column not named here is silently dropped, so
-- adding one to the table is only half of adding it to the pipeline. Everything else about
-- this function is unchanged -- see supabase/schemas/emails.sql for why the key travels on
-- `apikey` rather than `Authorization`, and why delivery is best effort.
create or replace function public.send_email () returns trigger language plpgsql security definer
set
	"search_path" to '' as $$
declare
  -- btrim so a secret pasted with a stray newline or space still works.
  _key text := btrim(coalesce(private.get_secret('secret_key'), ''));
  _url text := btrim(coalesce(private.get_secret('supabase_url'), ''));
  -- The application origin the rendered links should point at. Falls back to
  -- production, so an unconfigured project behaves as it did before.
  _origin text := public.site_origin();
begin
  -- Delivery is BEST EFFORT. The row in public.emails is the durable record that a message
  -- was meant to go out; whether the edge function can be reached is a deployment concern
  -- and must never roll back the caller's transaction.
  if _key = '' or _url = '' then
    raise warning 'send_email: % is not configured, so email % was recorded but not delivered',
      case when _url = '' then 'the supabase_url vault secret' else 'the secret_key vault secret' end,
      new.id;
    return new;
  end if;
  begin
    -- Post to the Resend edge function. If the supabase URL is set to localhost, replace it with host.docker.internal so we hit the host machine, not the container.
    -- The key goes on `apikey`: `Authorization: Bearer` is reserved for JWTs, and the newer
    -- opaque `sb_secret_...` keys are rejected there.
    perform net.http_post(
      url:=replace(_url, '127.0.0.1', 'host.docker.internal') || '/functions/v1/resend',
      headers:=jsonb_build_object(
          'Content-Type', 'application/json',
          'apikey', _key
      )::jsonb,
      body:=jsonb_build_object(
        'to', new.email,
        -- to_jsonb of a null array yields JSON null, which the edge function's
        -- `.nullish()` schema accepts, so a message with no Cc is indistinguishable from
        -- one sent before the column existed.
        'cc', to_jsonb(new.cc),
        -- Null means "the stewards", which the edge function substitutes. Only SECURITY
        -- DEFINER functions can set it -- the table's INSERT privilege is revoked from
        -- authenticated and anon -- which is the same property that keeps `to` safe.
        'reply_to', new.reply_to,
        'subject', new.subject,
        'message', new.message,
        'event', new.event,
        'args', new.args,
        'origin', _origin
      )
    );
  exception when others then
    -- pg_net validates the URL synchronously, so a malformed value raises here rather than
    -- in the background worker. Warn and carry on.
    raise warning 'send_email: email % was recorded but could not be queued for delivery: % (%)',
      new.id, sqlerrm, sqlstate;
  end;
  return new;
end;
$$;

alter function public.send_email () OWNER to "postgres";

--------------------------------------
-- 3. Per-scholar notification preferences.
--
-- The platform's first, so its shape sets the pattern. A column on public.scholars would
-- have been less machinery and was rejected on two counts. Scholar metadata is world
-- readable ("Scholar metadata is public" selects using (true)), so a preference column
-- there publishes everyone's mute list to anyone signed in. And a column can never express
-- "this notice from that venue but not this one" -- a plausible next ask for someone who
-- leads three venues -- whereas adding a nullable `venue` column to this table later does,
-- without a rewrite.
--
-- Absence is the default, and the default is on. There is no row until a scholar turns
-- something off, so there is nothing to backfill, and a template marked `optional` later
-- needs no migration at all.
create table if not exists public.notification_settings (
	-- The scholar whose preference this is.
	scholar uuid not null,
	-- The template key it governs: a key of `Emails` marked `optional` in
	-- supabase/functions/_shared/templates.ts. Deliberately unconstrained -- a CHECK here
	-- would be a second copy of the registry living in SQL and drifting from it, and an
	-- unrecognized key is simply inert: nothing reads it.
	event text not null,
	-- False to silence it. A row saying true is equivalent to no row, and both are allowed
	-- so the client can write the preference without deciding whether to delete instead.
	enabled boolean not null,
	-- When it was last changed.
	created_at timestamp with time zone default now() not null
);

alter table public.notification_settings OWNER to "postgres";

grant all on table public.notification_settings to "anon";

grant all on table public.notification_settings to "authenticated";

grant all on table public.notification_settings to "service_role";

alter table only public.notification_settings
drop constraint if exists notification_settings_pkey;

alter table only public.notification_settings
add constraint notification_settings_pkey primary key (scholar, event);

alter table only public.notification_settings
drop constraint if exists notification_settings_scholar_fkey;

alter table only public.notification_settings
add constraint notification_settings_scholar_fkey foreign KEY (scholar) references public.scholars (id) on delete CASCADE;

alter table public.notification_settings ENABLE row LEVEL SECURITY;

-- Deliberately NO column-level write boundary here, unlike public.scholars and
-- public.volunteers. Those needed one because a column carried something the row policy did
-- not cover: `steward` is privilege, `orcid` and `email` are identity, `roleid` decided a
-- welcome grant. Every column here is part of "which of my own preferences this is", and
-- the policy below pins the only thing that matters -- a scholar cannot write, or reassign
-- a row to, anybody else. Repointing `event` on one's own row reaches nothing a plain
-- INSERT could not.
--
-- It would also break the ordinary write. PostgREST's upsert compiles to
-- `insert ... on conflict do update set` over EVERY column in the payload, and Postgres
-- checks column privileges for that set-list at plan time -- so revoking `scholar` and
-- `event` makes even the first, non-conflicting insert fail with 42501.

drop policy if exists "scholars can read their own notification settings" on public.notification_settings;

-- Deliberately NOT public, unlike the rest of a scholar's profile. Which notices someone
-- has silenced is nobody else's business, and keeping it private is the whole reason this
-- is a table rather than a column on the world-readable scholars row.
create policy "scholars can read their own notification settings" on public.notification_settings for
select
	to authenticated using (
		scholar=(
			select
				auth.uid ()
		)
	);

drop policy if exists "scholars can set their own notification settings" on public.notification_settings;

create policy "scholars can set their own notification settings" on public.notification_settings for insert to authenticated
with
	check (
		scholar=(
			select
				auth.uid ()
		)
	);

drop policy if exists "scholars can change their own notification settings" on public.notification_settings;

create policy "scholars can change their own notification settings" on public.notification_settings
for update
	to authenticated using (
		scholar=(
			select
				auth.uid ()
		)
	)
with
	check (
		scholar=(
			select
				auth.uid ()
		)
	);

drop policy if exists "scholars can clear their own notification settings" on public.notification_settings;

-- Deleting a row restores the default, which is on. Permitted so the client has a way back
-- to "unset" rather than only to "explicitly true".
create policy "scholars can clear their own notification settings" on public.notification_settings for DELETE to authenticated using (
	scholar=(
		select
			auth.uid ()
	)
);

--------------------------------------
-- 4. The fan-out.
--
-- Owner-only, like public._welcome_volunteer beside it: this is a STEP of create_volunteer,
-- not an entry point. Its authorization is create_volunteer's, and that is the point --
-- there is no way to ask for this mail without also becoming a volunteer, and RR004 makes
-- that a once-per-(scholar, role) event forever, so it cannot be used to send twice.
--
-- Returns how many holders were addressed, 0 when nobody qualifies. Nothing reads the
-- number today; it exists so a caller can tell "nobody to tell" from "told somebody"
-- without querying the emails table.
create or replace function public._notify_new_volunteer (
	_venueid uuid,
	_roleid uuid,
	_scholarid uuid
) returns integer language plpgsql security definer
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

	select v.title into _venue_title from public.venues v where v.id = _venueid;
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
		and not exists (
			select 1
			from public.notification_settings n
			where n.scholar = s.id and n.event = 'NewVolunteer' and not n.enabled
		);

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
			_venueid::text,
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

--------------------------------------
-- 5. create_volunteer tells the venue.
--
-- Everything above the new block is unchanged; see 20260828010000 for the per-venue welcome
-- grant it settles.
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
		end if;
	exception when others then
		raise warning 'create_volunteer: volunteer % was created but the venue could not be notified: % (%)',
			_volunteer_id, sqlerrm, sqlstate;
	end;

	-- Return the new volunteer id and what the grant actually came to.
	return jsonb_build_object('volunteer_id', _volunteer_id, 'welcome_granted', _granted);
end;
$function$;

--------------------------------------
-- 6. Erasure reaches the two new columns.
--
-- forget_scholar scrubbed `where scholar = _scholar or sender = _scholar`. An address in
-- `cc`, or in `reply_to`, is matched by NEITHER: the Cc'd holders of a role are not the
-- row's `scholar`, and the volunteer a notice replies to is its `sender` only by
-- coincidence of this one template. So without this an erased scholar's address would have
-- survived indefinitely in mail about somebody else -- the exact thing erasure exists to
-- prevent, arriving through a column added two parts ago.
--
-- Ordering is load-bearing: scholars.email is nulled partway down this function, so the
-- address has to be captured before that happens. It is the only handle on those rows.
create or replace function public.forget_scholar (_scholar uuid) returns jsonb language plpgsql security definer
set
	search_path='' as $$
declare
	_placeholder text := 'erased-' || _scholar || '@invalid';
	_emails int;
	_copied int;
	_audit int;
	_old_email text;
begin
	if _scholar is null then
		raise exception 'forget_scholar requires a scholar id';
	end if;

	-- Captured BEFORE the scholars row below is scrubbed. Rows where this scholar was
	-- merely copied, or was the person replies went to, are reachable only by address.
	select email into _old_email from public.scholars where id = _scholar;

	-- The identity behind the account. The row stays so the foreign keys hold, but
	-- nothing in it points at a person any more, and the credentials are destroyed
	-- so the account cannot be used again.
	update auth.users
	set
		email = _placeholder,
		phone = null,
		encrypted_password = null,
		raw_user_meta_data = '{}'::jsonb,
		raw_app_meta_data = '{}'::jsonb,
		confirmation_token = '',
		recovery_token = '',
		email_change = ''
	where id = _scholar;

	-- ORCID is the login identity; `status` is free text the scholar wrote about
	-- themselves and can name anyone.
	update public.scholars
	set
		name = null,
		email = null,
		orcid = null,
		-- Erasure destroys the identity, so it must destroy the privilege with it. A
		-- tombstone that is still a steward appears on the public /about list as
		-- "anonymous", still satisfies isSteward(), and would satisfy set_steward's
		-- last-steward guard on behalf of a uuid nobody can sign into — letting the
		-- last real steward be demoted while nobody is left who can act.
		steward = false,
		-- Emptied rather than nulled: `status` is NOT NULL. It is free text the
		-- scholar wrote about themselves and can name anyone, so it has to go.
		status = '',
		available = false
	where id = _scholar;

	-- A pending verification holds an address that was never even confirmed.
	delete from public.email_verifications where scholar = _scholar;

	-- Queued and sent mail carries the address and, in `args`, rendered values that
	-- can include their name. The row stays as evidence that a message was sent;
	-- its contents do not.
	update public.emails
	set
		email = _placeholder,
		subject = null,
		message = null,
		args = '[]'::jsonb,
		-- Mail addressed TO this scholar may also have copied others and named a third
		-- party as its reply address. Neither belongs to the erased scholar, but both are
		-- contents of a message whose contents are being destroyed.
		cc = null,
		reply_to = null
	where scholar = _scholar or sender = _scholar;
	get diagnostics _emails = row_count;

	-- Mail about SOMEBODY ELSE that merely copied this scholar, or that replied to them.
	-- The rest of the row belongs to other people and stays; only this scholar's address
	-- leaves it.
	if _old_email is not null then
		update public.emails
		set
			cc = nullif(array_remove(cc, _old_email), '{}'::text[]),
			reply_to = case when reply_to = _old_email then null else reply_to end
		where (cc is not null and _old_email = any (cc))
			or reply_to = _old_email;
		get diagnostics _copied = row_count;
	else
		_copied := 0;
	end if;

	-- audit_log keeps WHOLE rows, so every edit this scholar's profile ever
	-- received contains their name and address. Scrub the payloads and the actor,
	-- leaving which table changed and when — the append-only guard permits exactly
	-- this much and nothing more.
	perform set_config('app.erasure', 'on', true);

	update public.audit_log
	set
		before = case when before is not null then '{}'::jsonb end,
		after = case when after is not null then '{}'::jsonb end
	where tbl = 'scholars' and row_id = _scholar;
	get diagnostics _audit = row_count;

	update public.audit_log set actor = null where actor = _scholar;

	-- token_events.actor is the only field here that names a person; the ownership
	-- columns are left untouched, because the ledger is reconstructed from them.
	update public.token_events set actor = null where actor = _scholar;

	perform set_config('app.erasure', '', true);

	insert into public.erasures (subject, completed_at)
	values (_scholar, now())
	on conflict (subject) do update set completed_at = now();

	return jsonb_build_object(
		'scholar', _scholar,
		'emails_scrubbed', _emails,
		-- Reported separately from emails_scrubbed: these rows were not scrubbed, only
		-- de-addressed, and the receipt should not imply that mail about other people was
		-- emptied out.
		'emails_uncopied', _copied,
		'audit_payloads_scrubbed', _audit
	);
end;
$$;

alter function public.forget_scholar (uuid) OWNER to "postgres";

--------------------------------------
-- 7. Export counts mail a scholar was copied on.
--
-- emails_received keyed on `m.scholar = _target`, which names only the To recipient. A
-- notice that copied someone is mail they actually received, and their own data export
-- said nothing about it.
create or replace function public.export_scholar_data (_scholar uuid default null) returns jsonb language plpgsql security definer
set
	search_path='' as $$
declare
	_caller uuid := (select auth.uid());
	_target uuid := coalesce(_scholar, _caller);
	_target_email text;
begin
	if _caller is null then
		raise exception 'Authentication required';
	end if;
	if _target <> _caller and not public.isSteward() then
		raise exception 'You can only export your own data' using errcode = 'RR006';
	end if;

	-- Resolved once rather than per row: emails.cc holds addresses, not ids.
	select email into _target_email from public.scholars s where s.id = _target;

	return jsonb_build_object(
		'exported_at', now(),
		'scholar', (select to_jsonb(s) from public.scholars s where s.id = _target),
		'volunteering', (select coalesce(jsonb_agg(to_jsonb(v)), '[]'::jsonb) from public.volunteers v where v.scholarid = _target),
		'submissions', (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from public.submissions x where _target = any (x.authors)),
		'assignments', (select coalesce(jsonb_agg(to_jsonb(a)), '[]'::jsonb) from public.assignments a where a.scholar = _target),
		'conflicts', (select coalesce(jsonb_agg(to_jsonb(c)), '[]'::jsonb) from public.conflicts c where c.scholarid = _target),
		'supported_proposals', (select coalesce(jsonb_agg(to_jsonb(p)), '[]'::jsonb) from public.supporters p where p.scholarid = _target),
		'thanks_written', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from public.thanks t where t.author = _target),
		'transactions', (select coalesce(jsonb_agg(to_jsonb(t) order by t.seq), '[]'::jsonb) from public.transactions t
			where t.creator = _target or t.from_scholar = _target or t.to_scholar = _target),
		'tokens_held', (select coalesce(jsonb_object_agg(currency, n), '{}'::jsonb)
			from (select currency, count(*) as n from public.tokens where scholar = _target group by currency) c),
		-- The ledger makes this possible for the first time: before token_events
		-- there was no record of where a scholar's tokens had been.
		'token_history', (select coalesce(jsonb_agg(to_jsonb(e) order by e.seq), '[]'::jsonb)
			from public.token_events e where e.scholar = _target or e.prev_scholar = _target),
		-- Addressed to them, or copied on it. SECURITY DEFINER, so the cc scan is not
		-- limited by the emails SELECT policy — which is what lets this report mail the
		-- scholar received but cannot read the row for. Only the event and the time, as
		-- before: the export says what arrived, not what it said.
		'emails_received', (select coalesce(jsonb_agg(jsonb_build_object('event', m.event, 'time_sent', m.time_sent)), '[]'::jsonb)
			from public.emails m
			where m.scholar = _target
				or (_target_email is not null and m.cc is not null and _target_email = any (m.cc))),
		-- Which notices they have silenced. Small, but it is a preference they set and so
		-- part of what the platform holds about them.
		'notification_settings', (select coalesce(jsonb_agg(to_jsonb(n)), '[]'::jsonb)
			from public.notification_settings n where n.scholar = _target)
	);
end;
$$;

alter function public.export_scholar_data (uuid) OWNER to "postgres";
