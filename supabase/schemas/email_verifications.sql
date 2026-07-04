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
create extension if not exists pgcrypto with schema extensions;

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
	expires_at timestamp with time zone default (now() + interval '15 minutes') not null
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
-- authenticated scholar and return the raw token so the app can build the URL and send
-- the branded email. Does NOT touch scholars.email — the old verified value is kept
-- until the new address is confirmed. Doubles as the "resend" and "change email" entry
-- point (upsert on the scholar primary key resets the token and the 15-minute clock).
create or replace function public.request_email_verification (_email text) RETURNS text LANGUAGE "plpgsql" SECURITY DEFINER
set
	"search_path" to 'public', 'pg_temp' as $$
declare
	_caller uuid := (select auth.uid());
	_token text;
begin
	if _caller is null then
		raise exception 'Authentication required';
	end if;
	if _email is null or _email !~ '^.+@.+\..+$' then
		raise exception 'A valid email address is required';
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

	return _token;
end;
$$;

alter function public.request_email_verification (text) OWNER to "postgres";

revoke execute on function public.request_email_verification (text) from public, anon;

grant execute on function public.request_email_verification (text) to authenticated;

-- verify_email: consume a token. Callable by anon because the link may be clicked while
-- logged out. Validates the token and its expiry; on success copies the candidate into
-- scholars.email and deletes the request. Returns a discriminated status so the verify
-- page can render distinct UI. The 256-bit token makes enumeration infeasible.
create or replace function public.verify_email (_token text) RETURNS jsonb LANGUAGE "plpgsql" SECURITY DEFINER
set
	"search_path" to 'public', 'pg_temp' as $$
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

	-- Commit the candidate. This is IDEMPOTENT: we deliberately do NOT delete the token
	-- here, so a repeat visit within the 15-minute window still returns 'verified' rather
	-- than a misleading 'invalid'. Single-use-with-delete breaks whenever the link is
	-- fetched more than once before the user acts — an email security scanner (SafeLinks,
	-- antivirus) prefetching it, or SvelteKit's hover-preload of the in-app dev link. A
	-- later verification request replaces this row (upsert on the scholar PK), and an
	-- expired revisit clears it.
	update public.scholars set email = _row.candidate_email where id = _row.scholar;

	return jsonb_build_object(
		'status', 'verified',
		'scholar', _row.scholar,
		'email', _row.candidate_email
	);
end;
$$;

alter function public.verify_email (text) OWNER to "postgres";

revoke execute on function public.verify_email (text) from public;

grant execute on function public.verify_email (text) to anon, authenticated;
