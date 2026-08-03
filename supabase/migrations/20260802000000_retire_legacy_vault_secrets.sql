-- Retire the legacy vault secrets left over from the API key migration.
--
-- 20260719040000 moved both edge-function callers onto the `apikey` header and renamed the
-- vault secret `service_role_key` → `secret_key`, reading through a `coalesce` so a project
-- that had not yet been updated kept sending mail. That transition is over: as of
-- 2026-08-02 both hosted projects have `secret_key` set and neither has `service_role_key`,
-- and local development seeds `secret_key` from [db.vault] in supabase/config.toml. The
-- fallback now only makes the code read as though a migration were still in progress.
--
-- Two secrets are dropped:
--
--   * `service_role_key` — superseded by `secret_key`, already absent from both hosted
--     vaults, so this deletes nothing in practice and exists to keep a project restored
--     from an old backup from silently authenticating on the stale value.
--   * `anon_key` — the publishable/anon key, read by nothing since the callers stopped
--     sending `Authorization: Bearer`. 20260719040000 already noted it could go. It is a
--     public key, so this is tidiness rather than a leak, but an unused credential sitting
--     in the vault invites someone to wire it back up.
--
-- Deleting from vault.secrets here — rather than by hand in the Dashboard, as the *creation*
-- of these secrets was done — is safe precisely because it is a deletion: it needs no secret
-- value in the repository, and it is idempotent. Nothing in this file resembles the
-- [db.vault] literal hazard described in supabase/config.toml, which is about `db push`
-- overwriting hosted values with local ones.

-- Warn rather than raise if `secret_key` is missing. The migrate job runs with no .env, so
-- the [db.vault] entries resolve to empty and this is expected there; and send_email() is
-- best effort by design (20260720010000) and already degrades to a warning. Failing the
-- migration would turn a configuration gap into a deploy outage.
do $$
begin
  if coalesce(btrim(private.get_secret('secret_key')), '') = '' then
    raise warning 'retire_legacy_vault_secrets: no secret_key vault secret is set. Mail will not be delivered until one is added (Project Settings → Vault).';
  end if;
end $$;

-- send_email(), unchanged from 20260720010000 except that `_key` no longer falls back to
-- the `service_role_key` secret.
create or replace function public.send_email () returns trigger language plpgsql security definer
set
	"search_path" to '' as $$
declare
  -- btrim so a secret pasted with a stray newline or space still works.
  _key text := btrim(coalesce(private.get_secret('secret_key'), ''));
  _url text := btrim(coalesce(private.get_secret('supabase_url'), ''));
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
        'args', new.args
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

-- The cron command is stored as text in cron.job, so dropping the fallback there means
-- re-scheduling. Same schedule and same body as 20260719040000.
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
            'apikey', private.get_secret('secret_key')
        )::jsonb,
        body:=jsonb_build_object()
       );
    $$
	);

-- Drop the retired secrets last, so the definitions above are already in place if this
-- migration is interrupted partway. Both are no-ops on a fresh local database, which seeds
-- only supabase_url, secret_key and site_url.
delete from vault.secrets where name in ('service_role_key', 'anon_key');
