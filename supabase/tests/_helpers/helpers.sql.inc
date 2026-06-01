-- Shared helpers for the pgTAP RLS test suite.
--
-- This file is NOT named *.sql on purpose: `supabase test db` runs pg_prove
-- over supabase/tests/**/*.sql and would otherwise try to run it as a (planless)
-- test and fail. Each test pulls it in with `\ir ../_helpers/helpers.sql.inc`.
--
-- Everything here is created inside the test's own `begin ... rollback`, so the
-- `tests` schema, helper functions, and any fixtures vanish when the test ends.
--
-- Auth model: tests run as the superuser (`postgres`). To exercise RLS we switch
-- the local role to `authenticated`/`anon` and set `request.jwt.claims.sub`,
-- exactly mirroring how the end2end tests probe RLS. Always create fixtures
-- while in the owner context (before authenticate_as, or after
-- clear_authentication) so inserts bypass RLS and can write auth.users.

create schema if not exists tests;

--------------------------------------------------------------------------------
-- Auth context. These are SECURITY INVOKER (default): a SET LOCAL inside a
-- SECURITY DEFINER function would be unwound on return. They work because the
-- session user is the postgres superuser, which may SET ROLE to anything.
--------------------------------------------------------------------------------

-- Become the given scholar: role `authenticated` with a matching JWT sub claim.
create or replace function tests.authenticate_as (p_user uuid) returns void language plpgsql as $$
begin
	perform set_config('role', 'authenticated', true);
	perform set_config(
		'request.jwt.claims',
		json_build_object('sub', p_user::text, 'role', 'authenticated')::text,
		true
	);
end;
$$;

-- Become an anonymous visitor: role `anon`, no sub claim (auth.uid() is null).
create or replace function tests.authenticate_as_anon () returns void language plpgsql as $$
begin
	perform set_config('role', 'anon', true);
	perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
end;
$$;

-- Return to the owner context (bypasses RLS; needed for fixture setup).
create or replace function tests.clear_authentication () returns void language plpgsql as $$
begin
	perform set_config('role', 'postgres', true);
	perform set_config('request.jwt.claims', '', true);
end;
$$;

--------------------------------------------------------------------------------
-- Fixture builders. SECURITY DEFINER (owner = postgres) so they may insert into
-- auth.* and bypass RLS regardless of the current role. Each returns the new id.
--------------------------------------------------------------------------------

-- Create an auth user + scholar. The handle_new_scholar trigger creates the
-- scholars row from the auth.users insert; we then set name/steward.
create or replace function tests.create_scholar (p_email text default null, p_steward boolean default false)
returns uuid language plpgsql security definer set search_path to '' as $$
declare
	new_id uuid := gen_random_uuid();
	addr text := coalesce(p_email, new_id::text || '@test.local');
begin
	insert into auth.users (
		instance_id, id, aud, role, email,
		encrypted_password, email_confirmed_at,
		raw_app_meta_data, raw_user_meta_data,
		created_at, updated_at,
		confirmation_token, recovery_token, email_change_token_new, email_change
	) values (
		'00000000-0000-0000-0000-000000000000', new_id, 'authenticated', 'authenticated', addr,
		'', now(),
		'{"provider":"email","providers":["email"]}', '{}',
		now(), now(),
		'', '', '', ''
	);
	insert into public.scholars (id, email, name, steward)
	values (new_id, addr, 'Test Scholar', p_steward)
	on conflict (id) do update set name = excluded.name, steward = excluded.steward;
	return new_id;
end;
$$;

-- Create a currency with the given minters (must be non-empty).
create or replace function tests.create_currency (p_minters uuid[])
returns uuid language plpgsql security definer set search_path to '' as $$
declare new_id uuid := gen_random_uuid();
begin
	insert into public.currencies (id, name, minters)
	values (new_id, 'Test Currency', p_minters);
	return new_id;
end;
$$;

-- Create a venue. admins must be non-empty and must NOT overlap the currency's
-- minters (the no_minter_admins trigger enforces this).
create or replace function tests.create_venue (
	p_currency uuid,
	p_admins uuid[],
	p_welcome integer default 0,
	p_anonymous_assignments boolean default true
) returns uuid language plpgsql security definer set search_path to '' as $$
declare new_id uuid := gen_random_uuid();
begin
	insert into public.venues (id, title, currency, welcome_amount, admins, inactive, anonymous_assignments)
	values (new_id, 'Test Venue', p_currency, p_welcome, p_admins, null, p_anonymous_assignments);
	return new_id;
end;
$$;

-- Create a role at a venue.
create or replace function tests.create_role (
	p_venue uuid,
	p_priority integer default 0,
	p_approver uuid default null,
	p_biddable boolean default false,
	p_invited boolean default false
) returns uuid language plpgsql security definer set search_path to '' as $$
declare new_id uuid := gen_random_uuid();
begin
	insert into public.roles (id, venueid, name, invited, biddable, approver, priority)
	values (new_id, p_venue, 'Test Role', p_invited, p_biddable, p_approver, p_priority);
	return new_id;
end;
$$;

-- Volunteer a scholar for a role (accepted by default).
create or replace function tests.create_volunteer (
	p_scholar uuid,
	p_role uuid,
	p_accepted public.invited default 'accepted'
) returns uuid language plpgsql security definer set search_path to '' as $$
declare new_id uuid := gen_random_uuid();
begin
	insert into public.volunteers (id, scholarid, roleid, expertise, accepted)
	values (new_id, p_scholar, p_role, '', p_accepted);
	return new_id;
end;
$$;

-- Create a submission type at a venue.
create or replace function tests.create_submission_type (p_venue uuid)
returns uuid language plpgsql security definer set search_path to '' as $$
declare new_id uuid := gen_random_uuid();
begin
	insert into public.submission_types (id, venue, name)
	values (new_id, p_venue, 'Test Type');
	return new_id;
end;
$$;

-- Create a submission. payments/transactions are sized to match authors.
create or replace function tests.create_submission (
	p_venue uuid,
	p_submission_type uuid,
	p_authors uuid[]
) returns uuid language plpgsql security definer set search_path to '' as $$
declare new_id uuid := gen_random_uuid();
begin
	insert into public.submissions (id, venue, externalid, submission_type, authors, payments, transactions)
	values (
		new_id, p_venue, new_id::text, p_submission_type, p_authors,
		array_fill(0, array[cardinality(p_authors)]),
		array_fill('00000000-0000-0000-0000-000000000000'::uuid, array[cardinality(p_authors)])
	);
	return new_id;
end;
$$;

-- Assign a scholar to a submission for a role (approved by default).
create or replace function tests.create_assignment (
	p_venue uuid,
	p_submission uuid,
	p_scholar uuid,
	p_role uuid,
	p_approved boolean default true,
	p_bid boolean default false
) returns uuid language plpgsql security definer set search_path to '' as $$
declare new_id uuid := gen_random_uuid();
begin
	insert into public.assignments (id, venue, submission, scholar, role, bid, approved)
	values (new_id, p_venue, p_submission, p_scholar, p_role, p_bid, p_approved);
	return new_id;
end;
$$;

-- The auth context helpers are called AFTER switching to authenticated/anon, so
-- those roles need access to the tests schema and its functions.
grant usage on schema tests to authenticated, anon, service_role;
grant execute on all functions in schema tests to authenticated, anon, service_role;
