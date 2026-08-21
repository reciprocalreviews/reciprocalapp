-- Two fixes found while verifying staging.
--
-- 1. Email delivery must never abort the caller's transaction.
--
--    send_email() guarded the secret key but handed the URL straight to net.http_post, so a
--    deployment problem became a hard failure for whoever happened to be queuing the email.
--    Observed on staging twice: a missing `supabase_url` raised 23502 (null value in
--    http_request_queue.url), and a value pasted with a trailing newline raised XX000
--    ("URL using bad/illegal format"). Either way the trigger raised, the INSERT rolled
--    back, and the RPC that queued the email failed.
--
--    The blast radius is much wider than email verification. Any action that queues mail —
--    volunteering, proposing a venue, declining a transaction — would fail outright and
--    roll back the user's actual work, on a project whose only fault is a mistyped secret.
--
--    Delivery is now best effort: the row in public.emails is the durable record that a
--    message was meant to go out, and reaching the edge function is a deployment concern.
--    A missing or unusable secret logs a warning and leaves the row in place; the caller's
--    work commits. Secrets are trimmed, so whitespace pasted into the Vault stops mattering.
--
-- 2. ORCID supplies given_name/family_name, never `name`.
--
--    handle_new_scholar read `raw_user_meta_data->>'name'`, which ORCID does not send, so
--    every scholar created through ORCID sign-in got a null name. Confirmed against a real
--    staging account: the metadata keys are sub, given_name, family_name, iss, aud, iat,
--    exp, email_verified, phone_verified. `name` is preferred when a provider does send it,
--    with given/family composed as the fallback.
--------------------------------------
-- 1. Best-effort delivery.
create or replace function public.send_email () returns trigger language plpgsql security definer
set
	"search_path" to '' as $$
declare
  -- btrim so a secret pasted with a stray newline or space still works. That exact mistake
  -- cost an afternoon of debugging on staging.
  _key text := btrim(coalesce(private.get_secret('secret_key'), private.get_secret('service_role_key'), ''));
  _url text := btrim(coalesce(private.get_secret('supabase_url'), ''));
begin
  -- Not configured: record the email, warn, and let the caller's transaction commit.
  if _key = '' or _url = '' then
    raise warning 'send_email: % is not configured, so email % was recorded but not delivered',
      case when _url = '' then 'the supabase_url vault secret' else 'the secret_key vault secret' end,
      new.id;
    return new;
  end if;

  -- Configured but unreachable, malformed, or otherwise failing: same principle. pg_net
  -- validates the URL synchronously, so a bad value raises here rather than in the
  -- background worker — and without this handler that raise propagates into the caller.
  begin
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
    raise warning 'send_email: email % was recorded but could not be queued for delivery: % (%)',
      new.id, sqlerrm, sqlstate;
  end;

  return new;
end;
$$;

alter function public.send_email () OWNER to "postgres";

--------------------------------------
-- 2. Compose the scholar's name from whatever the provider actually sends.
create or replace function public.handle_new_scholar () returns "trigger" language "plpgsql" security definer
set
	"search_path" to '' as $$
begin
  insert into public.scholars (id, orcid, name)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data->>'orcid',
      new.raw_user_meta_data->>'provider_id',
      new.raw_user_meta_data->>'sub'
    ),
    -- ORCID sends given_name/family_name and no `name`. Prefer `name` for providers that do
    -- send it; fall back to the composed form. Left null when the provider sends neither,
    -- so the scholar can supply one rather than being given a placeholder.
    coalesce(
      nullif(btrim(new.raw_user_meta_data->>'name'), ''),
      nullif(btrim(concat_ws(' ',
        new.raw_user_meta_data->>'given_name',
        new.raw_user_meta_data->>'family_name'
      )), '')
    )
  );
  return new;
end;
$$;

alter function public.handle_new_scholar () OWNER to "postgres";

-- Backfill scholars already created without a name, using the same rule.
update public.scholars s
set
	name = coalesce(
		nullif(btrim(u.raw_user_meta_data ->> 'name'), ''),
		nullif(btrim(concat_ws(' ', u.raw_user_meta_data ->> 'given_name', u.raw_user_meta_data ->> 'family_name')), '')
	)
from
	auth.users u
where
	u.id = s.id
	and s.name is null
	and coalesce(
		nullif(btrim(u.raw_user_meta_data ->> 'name'), ''),
		nullif(btrim(concat_ws(' ', u.raw_user_meta_data ->> 'given_name', u.raw_user_meta_data ->> 'family_name')), '')
	) is not null;
