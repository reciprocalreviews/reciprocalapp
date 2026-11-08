--------------------------------------
-- Record what happens to mail we try to send (#27).
--
-- public.send_email() posted to the `resend` edge function through pg_net and threw the
-- result away. pg_net is asynchronous -- net.http_post returns a handle immediately and the
-- HTTP outcome lands later in net._http_response -- so nothing in this database ever learned
-- whether a message left the building. A missing vault secret, a Resend refusal and a
-- delivered message were indistinguishable afterwards, and the scholar was told "we sent you
-- a link" in all three cases.
--
-- This migration adds four columns to public.emails, teaches send_email() to write them
-- (including on both of its existing best-effort failure paths, which previously only
-- raised a warning), and adds a bounded reconciler on a five-minute schedule to turn
-- pg_net's asynchronous answers into durable verdicts before pg_net garbage-collects them
-- at its six-hour TTL.
--
-- Paired with supabase/schemas/emails.sql. Must run BEFORE
-- 20260910020000_verification_pending_and_resend.sql, which reads public.emails.delivery.
--------------------------------------
-- Columns. Deliberately NOT backfilled: `delivery is null` means "nothing was recorded",
-- which is the truth about every row written before this ran. Writing 'sent' would put a
-- reassuring lie in the one column that exists to be honest.
alter table public.emails
add column if not exists request_id bigint;

alter table public.emails
add column if not exists delivery text;

alter table public.emails
add column if not exists delivery_detail text;

alter table public.emails
add column if not exists delivery_at timestamp with time zone;

-- A four-value vocabulary, enforced rather than conventional: the interface branches on
-- these words and the reconciler writes them, so a typo in either would otherwise become a
-- state nothing handles and nothing reports.
alter table public.emails
drop constraint if exists emails_delivery_status;

alter table public.emails
add constraint emails_delivery_status check (
	delivery is null
	or delivery in ('queued', 'sent', 'failed', 'unknown')
);

-- PARTIAL, so the reconciler's cost is the size of the UNRESOLVED set rather than of all
-- mail ever sent. This is the lesson 20260830030000 learned the hard way on
-- reconcile_ledger: a monitoring job whose cost grows with history eventually stops
-- finishing, and a cron job that times out fails silently -- no row, no mail, no alarm.
create index if not exists emails_delivery_unresolved_index on public.emails using btree (time_sent)
where
	delivery in ('queued', 'unknown');

--------------------------------------
-- send_email(): capture pg_net's request id instead of discarding it, and record a terminal
-- 'failed' on both paths that previously only warned.
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
-- Scheduling. cron.job is cluster state rather than schema, so it lives in the migration
-- and not in supabase/schemas/ -- the same reasoning reconciliations.sql gives, and the
-- reason remind-daily was silently lost once (20260517230819).
--
-- Every five minutes, offset to :03/:08/.../:58 so it never lands on :00 (remind-daily) or
-- :15 (reconcile-ledger). Five minutes against pg_net's six-hour TTL is a 72x margin on the
-- only deadline that matters, and the run is cheap: its scan is the partial index over
-- unresolved rows, not the mail log.
--
-- Guarded unschedule: cron.unschedule(name) RAISES if the job is absent, which it is on a
-- fresh database and on any project restored from a backup taken before this migration.
-- reconcile-ledger's bare call worked only because that job already existed.
select
	cron.unschedule ('reconcile-email-delivery')
where
	exists (
		select
			1
		from
			cron.job
		where
			jobname = 'reconcile-email-delivery'
	);

select
	cron.schedule (
		'reconcile-email-delivery',
		'3-58/5 * * * *',
		$job$
		select
			public.reconcile_email_delivery ()
		$job$
	);
