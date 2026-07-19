-- Require a service_role caller for the edge functions.
--
-- public.send_email() and the remind-daily cron job invoke the `resend` and `remind`
-- edge functions through pg_net, and both authenticated with the ANON key. That key is
-- public by design — it ships in the browser bundle as PUBLIC_SUPABASE_ANON_KEY — and
-- the platform's verify_jwt gate accepts any valid project JWT, so both endpoints were
-- reachable by anyone. `resend` takes its recipient, subject, and body straight from the
-- request body, which made it an open relay for mail branded as
-- notifications@reciprocal.reviews; `remind` could be fired repeatedly to spam scholars
-- and advance the timestamps that suppress the real daily run.
--
-- The handlers now reject any caller whose JWT `role` claim isn't `service_role` (see
-- supabase/functions/_shared/auth.ts), so both callers here switch from the `anon_key`
-- vault secret to `service_role_key`.
--
-- DEPLOYMENT: every hosted project needs a `service_role_key` vault secret added by hand
-- before this takes effect (Dashboard → Project Settings → Vault, value from Project
-- Settings → API). Local development seeds it from SUPABASE_SERVICE_ROLE_KEY via
-- [db.vault] in supabase/config.toml. If the secret is absent, send_email() raises a
-- warning and the request goes out unauthenticated — the function rejects it, so mail
-- stops rather than being delivered by an unauthorized path.

create or replace function public.send_email () returns trigger language plpgsql security definer
set
	"search_path" to '' as $$
declare
  _key text := private.get_secret('service_role_key');
begin
  -- Surface a misconfigured deployment in the Postgres logs. pg_net posts
  -- asynchronously and swallows failures, so without this a missing secret would look
  -- exactly like mail silently not arriving.
  if _key is null or _key = '' then
    raise warning 'send_email: the service_role_key vault secret is missing, so email % cannot be delivered', new.id;
  end if;
  -- Post to the Resend edge function. If the supabase URL is set to localhost, replace it with host.docker.internal so we hit the host machine, not the container.
  perform net.http_post(
    url:=replace(private.get_secret('supabase_url'), '127.0.0.1', 'host.docker.internal') || '/functions/v1/resend',
    headers:=jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || _key
    )::jsonb,
    body:=jsonb_build_object('to', new.email, 'subject', new.subject, 'message', new.message)
  );
  return new;
end;
$$;

alter function public.send_email () OWNER to "postgres";

-- Re-schedule the daily reminder with the same authorization change. cron.schedule
-- replaces a job of the same name, but unschedule first to match the pattern in
-- 20260517230819_restore_remind_cron.sql.
do $$
begin
  if exists (select 1 from cron.job where jobname = 'remind-daily') then
    perform cron.unschedule('remind-daily');
  end if;
end $$;

select
	cron.schedule (
		'remind-daily',
		'0 22 * * *',
		$$
    select
      net.http_post(
        url:=replace(private.get_secret('supabase_url'), '127.0.0.1', 'host.docker.internal') || '/functions/v1/remind',
        headers:=jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || private.get_secret('service_role_key')
        )::jsonb,
        body:=jsonb_build_object()
       );
    $$
	);
