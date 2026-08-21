-- Move the edge-function callers onto the `apikey` header and the `secret_key` vault
-- secret, so both API key formats work.
--
-- Supabase's newer API keys (`sb_publishable_...` / `sb_secret_...`) are opaque strings
-- rather than JWTs. Two consequences for the calls this project makes from Postgres:
--
--   * They must be sent on the `apikey` header. `Authorization: Bearer` is reserved for
--     JWTs, and a new-format key sent there is rejected as an invalid JWT.
--   * The edge functions can no longer authorize by decoding a `role` claim, because there
--     is no payload to decode. They now check that the caller presented one of the
--     project's secret keys (supabase/functions/_shared/auth.ts), which is format-agnostic.
--
-- The vault secret is renamed `service_role_key` → `secret_key` to match: the value may be
-- either a legacy `service_role` JWT or a new `sb_secret_...` key, and a name implying the
-- legacy format would be one more thing to remember incorrectly later. The rename is
-- backward compatible at read time — `coalesce` falls back to the old secret name, so a
-- project that has not yet had `secret_key` added keeps sending mail.
--
-- DEPLOYMENT: add a `secret_key` vault secret to each hosted project (any secret key —
-- legacy or new). The old `service_role_key` secret can be deleted once `secret_key` is in
-- place. The `anon_key` vault secret is no longer read by anything and can also be removed.

create or replace function public.send_email () returns trigger language plpgsql security definer
set
	"search_path" to '' as $$
declare
  -- Prefer the new name; fall back to the old one so this is safe to deploy before the
  -- vault secret is renamed in a hosted project.
  _key text := coalesce(private.get_secret('secret_key'), private.get_secret('service_role_key'));
begin
  -- Surface a misconfigured deployment in the Postgres logs. pg_net posts asynchronously
  -- and swallows failures, so without this a missing secret looks exactly like mail
  -- silently not arriving.
  if _key is null or _key = '' then
    raise warning 'send_email: no secret_key vault secret is configured, so email % cannot be delivered', new.id;
  end if;
  -- Post to the Resend edge function. If the supabase URL is set to localhost, replace it with host.docker.internal so we hit the host machine, not the container.
  perform net.http_post(
    url:=replace(private.get_secret('supabase_url'), '127.0.0.1', 'host.docker.internal') || '/functions/v1/resend',
    headers:=jsonb_build_object(
        'Content-Type', 'application/json',
        -- `apikey`, not `Authorization: Bearer` — see the note above.
        'apikey', _key
    )::jsonb,
    body:=jsonb_build_object(
      'to', new.email,
      'subject', new.subject,
      'message', new.message,
      'event', new.event,
      'args', new.args
    )
  );
  return new;
end;
$$;

alter function public.send_email () OWNER to "postgres";

-- Re-schedule the daily reminder with the same header and secret change.
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
            'apikey', coalesce(private.get_secret('secret_key'), private.get_secret('service_role_key'))
        )::jsonb,
        body:=jsonb_build_object()
       );
    $$
	);
