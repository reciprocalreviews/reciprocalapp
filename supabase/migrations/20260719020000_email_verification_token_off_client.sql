-- Keep the contact-email verification token out of the client, and stop accepting email
-- prose from callers (#27).
--
-- request_email_verification previously RETURNED THE RAW TOKEN to the browser, which then
-- built the link and sent the mail. Anyone could read that token out of the network tab
-- and immediately confirm an address they do not control, which is precisely what the
-- feature exists to prevent. It also meant the caller chose both the recipient (any
-- address they typed) and the message body — an open relay for branded mail.
--
-- The RPC now does all of it inside the database: it generates the token, builds the link
-- from the `site_url` vault secret, and queues the email itself. It returns nothing.
--
-- Because the body must not come from the caller, emails are now queued as an EVENT plus
-- ARGUMENTS and rendered at send time by the `resend` edge function from the shared
-- template registry (supabase/functions/_shared/templates.ts). `subject`/`message` become
-- nullable: rows queued this way carry structured args instead, which is a complete and
-- re-renderable record of what was sent.
--
-- DEPLOYMENT: every hosted project needs a `site_url` vault secret (the app origin, e.g.
-- https://reciprocal.reviews) before verification links can be built. Local development
-- seeds it via [db.vault] in supabase/config.toml.

--------------------------------------
-- emails: structured args, rendered at send time.
alter table public.emails
add column if not exists args jsonb not null default '[]'::jsonb;

alter table public.emails
alter column subject
drop not null;

alter table public.emails
alter column message
drop not null;

-- Pass the event and args through to the edge function so it can render when the body was
-- not supplied by the caller. Existing callers that still render their own subject/message
-- keep working unchanged.
create or replace function public.send_email () returns trigger language plpgsql security definer
set
	"search_path" to '' as $$
declare
  _key text := private.get_secret('service_role_key');
begin
  if _key is null or _key = '' then
    raise warning 'send_email: the service_role_key vault secret is missing, so email % cannot be delivered', new.id;
  end if;
  perform net.http_post(
    url:=replace(private.get_secret('supabase_url'), '127.0.0.1', 'host.docker.internal') || '/functions/v1/resend',
    headers:=jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || _key
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

--------------------------------------
-- request_email_verification: create (or replace) a pending verification for the
-- authenticated scholar and QUEUE the verification email. Returns nothing — the token is
-- never exposed to any caller. Does NOT touch scholars.email; the previously verified
-- address stands until the new one is confirmed. Doubles as the resend and change-email
-- entry point (the upsert resets the token and the 15-minute clock).
drop function if exists public.request_email_verification (text);

create or replace function public.request_email_verification (_email text) returns void language "plpgsql" security definer
set
	"search_path" to 'public', 'pg_temp' as $$
declare
	_caller uuid := (select auth.uid());
	_token text;
	_origin text := private.get_secret('site_url');
	_previous timestamptz;
begin
	if _caller is null then
		raise exception 'Authentication required';
	end if;
	if _email is null or _email !~ '^.+@.+\..+$' then
		raise exception 'A valid email address is required';
	end if;
	if _origin is null or _origin = '' then
		raise exception 'The site_url vault secret is not configured';
	end if;

	-- Rate limit. Each request emails a (possibly unverified, possibly someone else's)
	-- address, so without a cooldown this RPC is a mail amplifier. One per minute per
	-- scholar is well below any legitimate resend cadence.
	select created_at into _previous from public.email_verifications where scholar = _caller;
	if _previous is not null and _previous > now() - interval '1 minute' then
		raise exception 'Please wait a moment before requesting another verification email';
	end if;

	_token := encode(extensions.gen_random_bytes(32), 'hex');

	insert into public.email_verifications (scholar, token_hash, candidate_email, created_at, expires_at)
	values (
		_caller,
		encode(extensions.digest(_token, 'sha256'), 'hex'),
		lower(btrim(_email)),
		now(),
		now() + interval '15 minutes'
	)
	on conflict (scholar) do update
		set token_hash = excluded.token_hash,
			candidate_email = excluded.candidate_email,
			created_at = excluded.created_at,
			expires_at = excluded.expires_at;

	-- Queue the branded email. scholar AND sender are deliberately null: the emails SELECT
	-- policy grants reads to both the recipient and the sender, so attributing this row to
	-- the requester would let them read the token straight back out of the args — exactly
	-- the leak this migration closes. With both null, no policy branch matches and the row
	-- is unreadable by anyone. The body is rendered at send time from the VerifyEmail
	-- template, so no prose crosses the API.
	insert into public.emails (event, scholar, sender, venue, email, subject, message, args)
	values (
		'VerifyEmail',
		null,
		null,
		null,
		lower(btrim(_email)),
		null,
		null,
		jsonb_build_array(rtrim(_origin, '/') || '/verify/' || _token)
	);
end;
$$;

alter function public.request_email_verification (text) OWNER to "postgres";

revoke execute on function public.request_email_verification (text)
from
	public,
	anon;

grant execute on function public.request_email_verification (text) to authenticated;
