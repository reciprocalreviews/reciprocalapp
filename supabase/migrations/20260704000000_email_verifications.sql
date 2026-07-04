-- App-level contact-email verification (#27) + ORCID auth (#19).
--
-- Scholars now authenticate with ORCID (custom OIDC), which does not release an email.
-- We collect a contact email separately and verify ownership ourselves, decoupled from
-- Supabase auth. Mirrors supabase/schemas/email_verifications.sql, and updates
-- handle_new_scholar (supabase/schemas/scholars.sql) to populate orcid/name from the
-- OIDC metadata instead of copying an (absent, unverified) email.

--------------------------------------
-- On new-user signup, seed the scholar row from ORCID OIDC metadata. Do NOT copy an
-- email: scholars.email holds only a verified address, set later via verify_email.
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
		new.raw_user_meta_data->>'name'
	);
	return new;
end;
$$;

--------------------------------------
-- email_verifications table (pending, not-yet-verified contact emails + token hashes).
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.email_verifications (
	scholar uuid not null,
	token_hash text not null,
	candidate_email text not null,
	created_at timestamp with time zone default now() not null,
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

-- RLS enabled with no policies: all direct access denied; reachable only via the
-- SECURITY DEFINER RPCs below.
alter table public.email_verifications ENABLE row LEVEL SECURITY;

--------------------------------------
-- RPCs
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

revoke execute on function public.verify_email (text) from public;

grant execute on function public.verify_email (text) to anon, authenticated;
