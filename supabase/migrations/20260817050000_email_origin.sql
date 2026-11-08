-- Send email links to the environment the mail was sent from.
--
-- Every template hardcoded https://reciprocal.reviews, so mail from a local
-- stack or from staging pointed at production. That made both environments
-- untestable for anything that arrives by email — the whole pull-based
-- payment and compensation flow — since following a link left the environment
-- under test entirely.
--
-- The origin comes from the `site_url` vault secret, which already exists per
-- environment and already builds the one server-generated link we had (the
-- contact-email verification link). Two consumers need it and they reach the
-- database differently:
--
--   * `resend` renders queued mail, and is called by send_email(), which can
--     read the vault directly — so the origin travels in the POST body.
--   * `remind` runs from cron with service_role and never touches `emails`,
--     so it needs a way to ask. site_origin() is that, and is granted to
--     service_role alone; the value is a public URL, but there is no reason
--     to widen access beyond the one caller.
--
-- Both fall back to https://reciprocal.reviews when the secret is unset, so a
-- project that never configures it keeps today's behaviour rather than
-- sending links to nowhere.

create or replace function public.site_origin () returns text language sql security definer
set
	search_path = '' as $$
	select coalesce(nullif(btrim(coalesce(private.get_secret('site_url'), '')), ''),
	                'https://reciprocal.reviews');
$$;

revoke execute on function public.site_origin () from public, anon, authenticated;
grant execute on function public.site_origin () to service_role;

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
