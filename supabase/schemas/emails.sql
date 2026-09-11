--------------------------------------
-- Schema
--
-- The emails table is a log of all emails sent to scholars.
create table if not exists public.emails (
	-- The unique ID of the bid, automatically generated
	id uuid default gen_random_uuid() not null,
	-- The event type of the email
	event text not null,
	-- The optional scholar to whom the email was sent
	scholar uuid,
	-- The optional scholar whose action sent the email (null for system-generated emails)
	sender uuid,
	-- The optional venue for which the email was sent
	venue uuid,
	-- When the email was sent
	time_sent timestamp with time zone default now() not null,
	-- The email to whom the email was sent
	email text not null,
	-- The subject of the email. Null when the row was queued by the database as an
	-- event + args to be rendered at send time (see `args` below).
	subject text,
	-- The body of the email. Null for the same reason as `subject`.
	message text,
	-- Template arguments for `event`, used when subject/message are null. Mail whose
	-- recipient is chosen by a caller must not also have its body chosen by that caller,
	-- so those rows carry structured args and the `resend` edge function renders them from
	-- supabase/functions/_shared/templates.ts at send time. event + args is a complete,
	-- re-renderable record of what was sent.
	args jsonb default '[]'::jsonb not null,
	-- The rest of this message's recipients, when it is meant to be ONE shared thread
	-- rather than N private copies. Null for the vast majority of mail, which has a single
	-- recipient. Like `email`, it is resolved server-side from scholars.email and is never
	-- accepted from a caller -- see the note on the missing insert policy below.
	cc text[],
	-- Where a reply should go, when that is not the steward inbox. Null means stewards@,
	-- which is what every message sent before this column existed carried and what the
	-- `resend` function still substitutes. Never accepted from a caller either: it points
	-- replies at an address, so a caller-supplied value would be a redirect sitting inside
	-- genuinely branded mail.
	reply_to text,
	-- ---- Delivery outcome -----------------------------------------------------------
	-- Everything above records what we MEANT to send. These four record what happened to
	-- it, because until now nothing did: send_email() posted to the `resend` edge function
	-- through pg_net and threw the result away, so a refused send, a missing vault secret
	-- and a delivered message were indistinguishable afterwards. The scholar was told "we
	-- sent you a link" in all three cases, which is the failure this closes (#27).
	--
	-- These apply to ALL mail, not only verification. The trigger that writes them is
	-- generic, filtering by event would be strictly more code, and "which of last week's
	-- notices never left the building" is worth being able to ask about any of them.
	--
	-- The pg_net request id. net.http_post returns immediately with this; the HTTP result
	-- lands in net._http_response later and is garbage collected at pg_net.ttl (6 hours),
	-- in an UNLOGGED table that a restart truncates. That six-hour, restart-fragile window
	-- is why public.reconcile_email_delivery() runs on a schedule rather than this being
	-- resolved on demand: a 24-hour verification link outlives it four times over.
	request_id bigint,
	-- What became of it:
	--   queued  -- handed to pg_net, no answer yet
	--   sent    -- the edge function answered 2xx
	--   failed  -- it answered 4xx/5xx, timed out, errored, or was never posted at all
	--   unknown -- no response was ever found (the worker never ran, or the answer was
	--              discarded before the reconciler looked)
	--
	-- Null means nothing was recorded: every row written before this column existed, and
	-- any row inserted while the send trigger is disabled (the RLS tests, and
	-- supabase/dr/quarantine.sql). Deliberately NOT backfilled -- we do not know whether
	-- those messages arrived, and writing 'sent' would put a reassuring lie in the one
	-- column that exists to be honest.
	delivery text,
	-- Why, in words, for whoever is looking at the row: an HTTP status and the head of the
	-- response body, so a 502 (Resend refused the message) reads differently from a 400 (we
	-- could not render it). NEVER returned to a scholar -- it is the edge function's own
	-- diagnostics and can quote a payload. public.pending_email_verification() returns the
	-- one-word `delivery` instead.
	delivery_detail text,
	-- When `delivery` was last written, so a row stuck at 'queued' is visible as stuck
	-- rather than merely old.
	delivery_at timestamp with time zone
);

alter table public.emails OWNER to "postgres";

grant all on table public.emails to "anon";

grant all on table public.emails to "authenticated";

grant all on table public.emails to "service_role";

alter table only public.emails
add constraint "emails_pkey" primary key (id);

-- An empty array is not "no Cc": it is a list someone built and then emptied, and it would
-- travel to Resend as `cc: []`, which that API treats as a malformed field rather than an
-- absent one. Normalizing at the source makes `cc is null` the single unambiguous
-- "one recipient" test, so neither send_email() nor the edge function has to guess.
alter table only public.emails
add constraint "emails_cc_shape" check (
	cc is null
	or (
		cardinality(cc)>0
		and array_position(cc, null::text) is null
	)
);

-- A four-value vocabulary, enforced rather than conventional: the interface branches on
-- these words and the reconciler writes them, so a typo in either would otherwise become a
-- state nothing handles and nothing reports.
alter table only public.emails
add constraint "emails_delivery_status" check (
	delivery is null
	or delivery in ('queued', 'sent', 'failed', 'unknown')
);

alter table only public.emails
add constraint "emails_scholar_fkey" foreign KEY (scholar) references public.scholars (id);

alter table only public.emails
add constraint "emails_sender_fkey" foreign KEY (sender) references public.scholars (id);

alter table only public.emails
add constraint "emails_venue_fkey" foreign KEY (venue) references public.venues (id);

--------------------------------------
-- Indexes
--
create index emails_scholar_index on public.emails using btree (scholar);

create index emails_venue_index on public.emails using btree (venue);

-- The reconciler's driving scan, and the whole reason it can run every five minutes.
-- PARTIAL, so its cost is the size of the UNRESOLVED set rather than of all mail ever
-- sent. This is the lesson 20260830030000 learned the hard way on reconcile_ledger: a
-- monitoring job whose cost grows with history eventually stops finishing, and a cron job
-- that times out fails silently -- no row, no mail, no alarm.
create index emails_delivery_unresolved_index on public.emails using btree (time_sent)
where
	delivery in ('queued', 'unknown');

--------------------------------------
-- Security
--
alter table public.emails ENABLE row LEVEL SECURITY;

create policy "senders, recipients, and venue admins can see the emails sent" on public.emails for
select
	to authenticated using (
		(
			(
				(
					select
						auth.uid () as uid
				)=scholar
			)
			or (
				(
					select
						auth.uid () as uid
				)=sender
			)
			or (
				(venue is not null)
				and public.isAdmin (venue)
			)
		)
	);

-- There is deliberately NO insert policy. The AFTER INSERT trigger below sends branded
-- mail, so a policy allowing authenticated inserts made this an open relay: any signed-in
-- user could name any recipient with any subject and body. Sending now goes through
-- public.queue_email (and public.request_email_verification), which resolve recipients
-- server-side and render the body from the template registry at send time. The privilege
-- is revoked too, so a direct attempt fails cleanly with 42501 rather than an empty result.
--
-- `cc` and `reply_to` are MORE recipient surface, so they tighten this rule rather than
-- loosen it: neither may ever be written from a value that crossed the API. Neither
-- queue_email nor queue_steward_email accepts a parameter for either, and the only writer
-- is public._notify_new_volunteer, which resolves every address from scholars.email.
revoke insert on table public.emails
from
	authenticated,
	anon;

create policy "emails can't be edited" on public.emails
for update
	to authenticated using (false);

create policy "emails can't be deleted" on public.emails for DELETE to authenticated using (false);

--------------------------------------
-- Functions
--
-- Create a schema to store this private function that gets a vault secret.
create schema private;

-- to avoid this function in the API
create or replace function private.get_secret (secret_name text) RETURNS text LANGUAGE plpgsql SECURITY DEFINER
set
	"search_path" to '' as $$ 
declare
   secret text;
begin
   select decrypted_secret into secret from vault.decrypted_secrets where name = secret_name;
   return secret;
end;
$$;

alter function private.get_secret (secret_name text) OWNER to "postgres";

-- The application origin that email links should point at, from the `site_url`
-- vault secret that already exists per environment. Templates used to hardcode
-- the production host, which made anything arriving by email untestable
-- anywhere else — following a link left the environment under test. Falls back
-- to production so an unconfigured project keeps its previous behaviour.
--
-- send_email() reads the secret directly and passes the value to the `resend`
-- function; this wrapper exists for the `remind` cron, which never touches the
-- emails table and so has nothing to carry the value to it. service_role only:
-- the value is a public URL, but only that one caller needs it.
create or replace function public.site_origin () returns text language sql security definer
set
	search_path='' as $$
	select coalesce(nullif(btrim(coalesce(private.get_secret('site_url'), '')), ''),
	                'https://reciprocal.reviews');
$$;

revoke
execute on function public.site_origin ()
from
	public,
	anon,
	authenticated;

grant
execute on function public.site_origin () to service_role;

-- Calls the `resend` edge function, presenting one of the project's SECRET keys. It must
-- NOT use the publishable/anon key: that key is public (it ships in the browser bundle),
-- so authenticating with it would leave `resend` — which takes its recipient and template
-- arguments from the request — callable by anyone as an open relay for branded mail. The
-- function authorizes by comparing the presented key against the project's secret keys
-- (supabase/functions/_shared/auth.ts), which works for both a legacy `service_role` JWT
-- and a newer opaque `sb_secret_...` key. Hosted projects must have the `secret_key` and
-- `supabase_url` vault secrets set by hand; local dev seeds them from [db.vault] in
-- supabase/config.toml. There is no fallback to the older `service_role_key` secret name:
-- that transition finished, and the retired secret was dropped in 20260802000000.
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
  -- pg_net's handle on the request. Kept, where it used to be discarded: it is the only
  -- way to find the answer, which arrives asynchronously in net._http_response.
  _request_id bigint;
begin
  -- Delivery is still BEST EFFORT. The row in public.emails is the durable record that a
  -- message was meant to go out; whether the edge function can be reached is a deployment
  -- concern and must never roll back the caller's transaction. What changes here is that
  -- "best effort" stops meaning "unrecorded": both failure paths below now write a
  -- terminal delivery state, so the row says what happened instead of only leaving a
  -- warning in a log nobody reads.
  --
  -- The state is recorded with an UPDATE against the row we were just handed, not by
  -- assigning to NEW: this is an AFTER trigger, so the row is already written and NEW is a
  -- copy. That UPDATE is allowed despite the "emails can't be edited" policy (using(false))
  -- because this function is SECURITY DEFINER owned by postgres, which owns the table, and
  -- the table does not FORCE row level security -- so policies do not apply to it. The
  -- policy still binds `authenticated`, which is who it was written for.
  --
  -- AFTER rather than BEFORE, deliberately. A BEFORE INSERT trigger runs before the table's
  -- CHECK constraints and foreign keys (emails_cc_shape, emails_scholar_fkey, ...), so
  -- moving this earlier to make NEW writable would post the message to Resend and only then
  -- discover that the row it was sending is about to be rejected: mail sent on behalf of a
  -- row that never existed. One extra UPDATE is the cheaper half of that trade.
  if _key = '' or _url = '' then
    raise warning 'send_email: % is not configured, so email % was recorded but not delivered',
      case when _url = '' then 'the supabase_url vault secret' else 'the secret_key vault secret' end,
      new.id;
    update public.emails
    set delivery = 'failed',
        delivery_detail = 'not posted: the '
          || case when _url = '' then 'supabase_url' else 'secret_key' end
          || ' vault secret is not configured',
        delivery_at = now()
    where id = new.id;
    return new;
  end if;
  begin
    -- Post to the Resend edge function. If the supabase URL is set to localhost, replace it with host.docker.internal so we hit the host machine, not the container.
    -- The key goes on `apikey`: `Authorization: Bearer` is reserved for JWTs, and the newer
    -- opaque `sb_secret_...` keys are rejected there.
    select net.http_post(
      url:=replace(_url, '127.0.0.1', 'host.docker.internal') || '/functions/v1/resend',
      headers:=jsonb_build_object(
          'Content-Type', 'application/json',
          'apikey', _key
      )::jsonb,
      body:=jsonb_build_object(
        'to', new.email,
        -- to_jsonb of a null array yields JSON null, which the edge function's `.nullish()`
        -- schema accepts, so a message with no Cc is indistinguishable from one sent before
        -- the column existed.
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
    ) into _request_id;

    -- 'queued' is an honest non-answer, not a success. net.http_post returns the instant it
    -- has written a row to net.http_request_queue; nothing has been delivered yet and
    -- nothing may ever be. public.reconcile_email_delivery() turns this into a verdict.
    update public.emails
    set request_id = _request_id,
        delivery = 'queued',
        delivery_at = now()
    where id = new.id;
  exception when others then
    -- pg_net validates the URL synchronously, so a malformed value raises here rather than
    -- in the background worker. Warn, record it as terminal, and carry on.
    raise warning 'send_email: email % was recorded but could not be queued for delivery: % (%)',
      new.id, sqlerrm, sqlstate;
    update public.emails
    set delivery = 'failed',
        delivery_detail = 'not posted: ' || sqlerrm || ' (' || sqlstate || ')',
        delivery_at = now()
    where id = new.id;
  end;
  return new;
end;
$$;

alter function public.send_email () OWNER to "postgres";

-- Nobody but the owner. This runs from the send_on_email_insert trigger and is never called
-- directly, and it is SECURITY DEFINER over the mail log, so an EXECUTE grant to anon or
-- authenticated is pure surface. 20260831000000 revoked exactly this (its `_triggers` list);
-- the grants that used to stand here were left over from before that migration, and any
-- `create or replace` of this function re-opens the hole unless the revoke travels with it —
-- Supabase's default privileges re-grant EXECUTE to anon and authenticated at creation time.
-- supabase/tests/rls/definer_grants.sql check 1 is what catches it.
revoke
execute on function public.send_email ()
from
	public,
	anon,
	authenticated;

--------------------------------------
-- Triggers
--
create or replace trigger send_on_email_insert
after insert on public.emails for each row
execute function public.send_email ();

--------------------------------------
-- reconcile_email_delivery: turn pg_net's asynchronous answers into durable verdicts on
-- public.emails.
--
-- send_email() can only ever record 'queued': net.http_post returns a handle immediately
-- and the HTTP outcome lands later in net._http_response -- an UNLOGGED table that a
-- database restart truncates and that pg_net garbage-collects at pg_net.ttl, six hours by
-- default. Nothing read it, so every send looked identical from the outside.
--
-- Six hours is the number that decides the shape of this. A verification link now lives for
-- 24 hours, and the scholar most likely to ask "did that ever arrive?" is the one who comes
-- back tomorrow -- by which time the answer has been discarded. Resolving on demand inside
-- public.pending_email_verification() would therefore be right exactly when nobody needed it
-- and blank whenever they did, would turn a read into a write, and would give a
-- scholar-facing RPC a dependency on the privileged `net` schema. So this runs on a
-- schedule, follows the shape of reconcile_ledger (20260830030000), and covers all mail
-- rather than only verification.
--
-- Deliberately does NOT email the stewards, unlike reconcile_ledger. A steward notification
-- is itself a row in public.emails. If delivery is broken, the notice about broken delivery
-- fails too, is marked failed on the next pass, and produces another notice -- a loop driven
-- by a job that runs every five minutes. Signal reaches people through the columns, the
-- warning in the Postgres log, and the interface that shows a scholar their own link never
-- went out.
--
-- Scheduling lives in the migration, not here: cron.job is cluster state rather than schema,
-- captured separately by supabase/dr/dump.sh. See 20260910010000.
create or replace function public.reconcile_email_delivery () returns jsonb language plpgsql security definer
set
	search_path='' as $$
declare
	_started timestamptz := clock_timestamp();
	_sent int := 0;
	_failed int := 0;
	_unknown int := 0;
	_abandoned int := 0;
	_result jsonb;
begin
	-- 1. Every request pg_net has answered.
	--
	-- Bounded three ways, all load-bearing. `delivery in ('queued','unknown')` means 'sent'
	-- and 'failed' are terminal and never revisited. The seven-day floor means a response
	-- that never came stops being asked about rather than being re-scanned forever. And the
	-- partial index on emails matches that predicate exactly, so the scan is the size of the
	-- unresolved set, which in a healthy deployment is a handful of rows.
	--
	-- Re-checking 'unknown' is what makes this self-correcting: step 2 gives up on a request
	-- after fifteen minutes, and if pg_net answers later this statement upgrades it to a real
	-- verdict on the next pass. Running the function twice in a row changes nothing.
	with resolved as (
		update public.emails e
		set delivery = case
				-- Order matters. A timed-out or errored request can also carry a status
				-- code, and the transport failure is the more truthful description.
				when r.timed_out then 'failed'
				when r.error_msg is not null then 'failed'
				when r.status_code between 200 and 299 then 'sent'
				when r.status_code is not null then 'failed'
				else 'unknown'
			end,
			delivery_detail = case
				when r.timed_out then 'timed out waiting for the resend function'
				when r.error_msg is not null then left(r.error_msg, 500)
				when r.status_code between 200 and 299 then null
				-- The status is kept, not just the verdict: the `resend` function answers
				-- 502 when Resend REFUSED the message (bad key, unverified sender domain,
				-- rejected recipient) and 400 when it could not render or parse it at all.
				-- Those are different faults with different fixes, and collapsing them into
				-- "failed" would throw away the only thing that tells them apart.
				when r.status_code is not null then r.status_code || ': ' || left(coalesce(r.content, ''), 500)
				else 'pg_net recorded a response with no status, no error and no timeout'
			end,
			delivery_at = now()
		from net._http_response r
		where r.id = e.request_id
			and e.request_id is not null
			and e.delivery in ('queued', 'unknown')
			and e.time_sent > now() - interval '7 days'
		returning e.delivery as outcome
	)
	select
		count(*) filter (where outcome = 'sent'),
		count(*) filter (where outcome = 'failed'),
		count(*) filter (where outcome = 'unknown')
	into _sent, _failed, _unknown
	from resolved;

	-- 2. Requests with no answer at all, old enough that there is not going to be one.
	--
	-- Fifteen minutes against pg_net's five-second default request timeout: long enough that
	-- a busy worker is not mistaken for a lost one, short enough that a scholar refreshing
	-- their profile is not left staring at 'queued' forever. 'unknown' rather than 'failed'
	-- because the two causes are genuinely different and neither is knowable from here: the
	-- worker never ran, or it ran and the answer was discarded (restart, or pg_net.ttl)
	-- before this job looked. Claiming the mail failed would be a guess; saying we do not
	-- know is not.
	update public.emails e
	set delivery = 'unknown',
		delivery_detail = 'no response was recorded: the pg_net worker never ran, or the answer '
			|| 'was discarded (restart, or pg_net.ttl) before this job looked',
		delivery_at = now()
	where e.delivery = 'queued'
		and e.request_id is not null
		and e.time_sent < now() - interval '15 minutes'
		and e.time_sent > now() - interval '7 days'
		and not exists (select 1 from net._http_response r where r.id = e.request_id);

	get diagnostics _abandoned = row_count;

	_result := jsonb_build_object(
		'resolved', jsonb_build_object('sent', _sent, 'failed', _failed, 'unknown', _unknown),
		'abandoned', _abandoned,
		'duration_ms', (extract(epoch from clock_timestamp() - _started) * 1000)::integer
	);

	-- Visible in the Postgres log for anyone looking at the project. Not mail: see the
	-- loop described in the header comment.
	if _failed > 0 then
		raise warning 'reconcile_email_delivery: % message(s) could not be delivered', _failed;
	end if;

	return _result;
end;
$$;

alter function public.reconcile_email_delivery () OWNER to "postgres";

-- Explicitly revoked, not merely un-granted: Supabase's ALTER DEFAULT PRIVILEGES hands anon
-- and authenticated EXECUTE on every function created in `public` at creation time, and
-- `revoke ... from public` does not take those back. See 20260831000000. This one writes to
-- public.emails as its owner, so leaving it open would be a lever on the mail log.
revoke
execute on function public.reconcile_email_delivery ()
from
	public,
	anon,
	authenticated;

grant
execute on function public.reconcile_email_delivery () to service_role;

--------------------------------------
-- RPC (authoritative definition from migration 20260719030000_queue_email_rpc)
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
	if _scholars is not null then
		insert into public.emails (event, scholar, sender, venue, email, subject, message, args)
		select _event, s.id, _caller, null, s.email, null, null, to_jsonb(_args)
		from public.scholars s
		where s.id = any(_scholars) and s.email is not null;

		select coalesce(jsonb_agg(jsonb_build_object('name', s.name, 'email', s.email)), '[]'::jsonb)
		into _recipients
		from public.scholars s
		where s.id = any(_scholars) and s.email is not null;
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

revoke
execute on function public.queue_email (text, text[], uuid[], uuid)
from
	public,
	anon;

grant
execute on function public.queue_email (text, text[], uuid[], uuid) to authenticated;

--------------------------------------
-- The alias, defined once.
--
-- Hardcoded rather than configured: it is a property of the deployment's DNS, changes
-- about never, and a settings table would make a silent misconfiguration possible in the
-- one path that reports that other paths are broken. Mirrored in
-- supabase/functions/_shared/emailShell.ts as SUPPORT_EMAIL — keep the two in sync.
create or replace function public.steward_inbox () returns text language sql immutable
set
	"search_path" to '' as $$
	select 'stewards@reciprocal.reviews'::text;
$$;

alter function public.steward_inbox () OWNER to "postgres";

grant
execute on function public.steward_inbox () to authenticated;

--------------------------------------
-- queue_steward_email: queue a steward notification to the shared inbox.
--
-- Deliberately a separate function from queue_email rather than another branch inside it.
-- queue_email's security rests on never accepting a recipient: it resolves scholars by id
-- or reads a proposal's editors. This function accepts no recipient either — the address
-- is fixed — but it does bypass the "recipient must be a scholar with a verified email"
-- rule, so the safety has to come from somewhere else. It comes from the event whitelist:
-- without it, any authenticated user could render ANY template into the stewards' inbox,
-- which is precisely the mailbox least able to ignore what arrives.
--
-- The residual exposure is bounded and deliberate: an authenticated user can queue a
-- steward notification with argument values of their choosing. That is the same shape as
-- queue_email's residual (no prose, no links, attributable via emails.sender), and the
-- inbox is staffed by the people best placed to recognize junk.
create or replace function public.queue_steward_email (_event text, _args text[] default '{}') returns void language plpgsql security definer
set
	"search_path" to 'public',
	'pg_temp' as $$
declare
	_caller uuid := (select auth.uid());
begin
	if _caller is null then
		raise exception 'Authentication required';
	end if;
	-- Whitelist, not a blacklist: a template added later is un-sendable here until
	-- someone deliberately adds it, which is the failure direction we want.
	if _event is null or _event not in ('ProposalCreatedStewards', 'ReconciliationFailed') then
		raise exception 'Not a steward notification: %', coalesce(_event, 'null');
	end if;

	insert into public.emails (event, scholar, sender, venue, email, subject, message, args)
	values (_event, null, _caller, null, public.steward_inbox(), null, null, to_jsonb(_args));
end;
$$;

alter function public.queue_steward_email (text, text[]) OWNER to "postgres";

revoke
execute on function public.queue_steward_email (text, text[])
from
	public,
	anon;

grant
execute on function public.queue_steward_email (text, text[]) to authenticated;
