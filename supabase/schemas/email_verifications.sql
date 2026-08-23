--------------------------------------
-- TABLE
-- App-level contact-email verification (#27). This is deliberately independent of
-- Supabase auth: scholars authenticate with ORCID (which does not release an email),
-- so we collect a contact email separately and verify ownership ourselves. The
-- invariant that makes the rest of the app simple: public.scholars.email holds only a
-- VERIFIED address (or null) — this table holds the pending, not-yet-verified candidate
-- and a hash of the emailed token. On successful verification the candidate is copied
-- into scholars.email; until then the previously verified email (if any) is preserved.
--
-- The raw token lives only in the emailed URL; we store just its sha256 hash. There is
-- at most one active request per scholar (primary key on scholar), so re-requesting
-- (resend, or changing to a different address) simply replaces it and resets the clock.
create extension if not exists pgcrypto
with
	schema extensions;

create table if not exists public.email_verifications (
	-- The scholar requesting verification; one active request each.
	scholar uuid not null,
	-- sha256 hex hash of the raw token that was emailed.
	token_hash text not null,
	-- The unverified address awaiting confirmation.
	candidate_email text not null,
	-- When the request was made.
	created_at timestamp with time zone default now() not null,
	-- When the link expires (15 minutes after creation).
	expires_at timestamp with time zone default (now()+interval '15 minutes') not null
);

alter table public.email_verifications OWNER to "postgres";

alter table only public.email_verifications
add constraint "email_verifications_pkey" primary key ("scholar");

alter table only public.email_verifications
add constraint "email_verifications_scholar_fkey" foreign KEY ("scholar") references public.scholars ("id") on delete cascade;

create index email_verifications_token_hash_index on public.email_verifications using btree (token_hash);

grant all on table public.email_verifications to "anon";

grant all on table public.email_verifications to "authenticated";

grant all on table public.email_verifications to "service_role";

--------------------------------------
-- SECURITY
-- Enable RLS with NO policies for anon/authenticated: all direct access is denied.
-- The table holds a secret token hash and an unverified address, so it is reachable
-- only through the SECURITY DEFINER RPCs below (owner postgres).
alter table public.email_verifications ENABLE row LEVEL SECURITY;

--------------------------------------
-- FUNCTIONS
--
-- request_email_verification: create (or replace) a pending verification for the
-- authenticated scholar and QUEUE the branded email. Returns nothing: the raw token never
-- leaves the database. An earlier version returned it to the browser, which let anyone
-- read it from the network tab and confirm an address they did not control — defeating the
-- entire purpose of verifying. For the same reason the caller supplies neither the message
-- body nor the link's origin: this email's recipient is whatever address the caller typed,
-- so letting them choose the content too would make the pipeline an open relay.
--
-- Does NOT touch scholars.email — the old verified value is kept until the new address is
-- confirmed. Doubles as the "resend" and "change email" entry point (upsert on the scholar
-- primary key resets the token and the 15-minute clock).
--
-- Each failure carries a machine-readable `hint` so the interface can say which of the four
-- things went wrong. Without it every case collapsed into one generic "unable to send",
-- which told a rate-limited scholar nothing and made a missing vault secret look like a
-- transient delivery fault.
create or replace function public.request_email_verification (_email text) returns void language "plpgsql" security definer
set
	"search_path" to 'public',
	'pg_temp' as $$
declare
	_caller uuid := (select auth.uid());
	_token text;
	_origin text := private.get_secret('site_url');
	_previous timestamptz;
begin
	if _caller is null then
		raise exception 'Authentication required' using hint = 'auth_required';
	end if;
	if _email is null or _email !~ '^.+@.+\..+$' then
		raise exception 'A valid email address is required' using hint = 'invalid_email';
	end if;
	-- A deployment that has not had its `site_url` vault secret set cannot build a
	-- verification link. Say so, rather than letting it look like a delivery failure.
	if _origin is null or _origin = '' then
		raise exception 'The site_url vault secret is not configured' using hint = 'not_configured';
	end if;

	-- Rate limit. Each call emails an address the caller chose, so without a cooldown this
	-- RPC is a mail amplifier. One per minute is well below any legitimate resend cadence.
	select created_at into _previous from public.email_verifications where scholar = _caller;
	if _previous is not null and _previous > now() - interval '1 minute' then
		raise exception 'Please wait a moment before requesting another verification email' using hint = 'cooldown';
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

	-- scholar AND sender are deliberately null: the emails SELECT policy grants reads to
	-- both the recipient and the sender, so attributing this row to the requester would let
	-- them read the token back out of the args — the very leak this design closes. With
	-- both null no policy branch matches and the row is unreadable by anyone.
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

revoke
execute on function public.request_email_verification (text)
from
	public,
	anon;

grant
execute on function public.request_email_verification (text) to authenticated;

-- verify_email: consume a token. Callable by anon because the link may be clicked while
-- logged out. Validates the token and its expiry; on success copies the candidate into
-- scholars.email and deletes the request. Returns a discriminated status so the verify
-- page can render distinct UI. The 256-bit token makes enumeration infeasible.
create or replace function public.verify_email (_token text) RETURNS jsonb LANGUAGE "plpgsql" SECURITY DEFINER
set
	"search_path" to 'public',
	'pg_temp' as $$
declare
	_row public.email_verifications%rowtype;
begin
	select * into _row from public.email_verifications
	where token_hash = encode(extensions.digest(_token, 'sha256'), 'hex');

	if not found then
		return jsonb_build_object('status', 'invalid');
	end if;

	if _row.expires_at < now() then
		delete from public.email_verifications where scholar = _row.scholar;
		return jsonb_build_object('status', 'expired');
	end if;

	-- Idempotent commit: do NOT delete the token, so a repeat fetch within the validity
	-- window (email link scanner prefetch, or SvelteKit hover-preload) still returns
	-- 'verified' rather than a misleading 'invalid'. A later request replaces this row
	-- (upsert on the scholar PK); an expired revisit clears it.
	update public.scholars set email = _row.candidate_email where id = _row.scholar;

	return jsonb_build_object(
		'status', 'verified',
		'scholar', _row.scholar,
		'email', _row.candidate_email
	);
end;
$$;

alter function public.verify_email (text) OWNER to "postgres";

revoke
execute on function public.verify_email (text)
from
	public;

grant
execute on function public.verify_email (text) to anon,
authenticated;
