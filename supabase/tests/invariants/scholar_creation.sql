-- The path by which a scholar comes to exist at all.
--
-- public.scholars has exactly one creation path: the on_auth_user_created trigger on
-- auth.users, running handle_new_scholar. Nothing else may insert a row — the INSERT
-- policy is `with check (false)` — and the trigger fires once, when the account is
-- created, never again. An account that misses it is permanently unusable, and quietly:
-- the session is valid, but the app reads its signed-in scholar from this table, finds
-- nothing, and renders the person as anonymous with no way back.
--
-- That happened in production. It went unnoticed because nothing here checked, and it
-- could go unnoticed because the trigger lives on auth.users — outside the schema set
-- CI's drift guard compares (config.toml exposes only public and graphql_public). This
-- file is the check that was missing.
--
-- The fixture in _helpers used to hide it too: it upserted the scholar row, so the
-- entire suite passed identically whether or not the trigger existed. It now updates
-- and raises, which means a missing trigger fails nearly every test in the suite rather
-- than none of them.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

-- The iDs below are deliberately outside the 0000-0001-2345-679x block seed.sql uses:
-- scholars_orcid_unique is real, and a collision would abort the auth.users insert
-- rather than fail an assertion, which is a confusing way to learn that.

select tests.clear_authentication();

--------------------------------------------------------------------------------
-- The trigger and its function exist, and are enabled
--------------------------------------------------------------------------------
select has_function(
	'public', 'handle_new_scholar', array[]::text[],
	'handle_new_scholar exists'
);

select has_trigger(
	'auth', 'users', 'on_auth_user_created',
	'auth.users carries the on_auth_user_created trigger'
);

-- has_trigger is satisfied by a DISABLED trigger, which does not fire and would
-- orphan every signup exactly as a missing one does.
select is(
	(select tgenabled from pg_trigger where tgrelid = 'auth.users'::regclass
		and tgname = 'on_auth_user_created'),
	'O'::"char",
	'on_auth_user_created is enabled, not merely present'
);

--------------------------------------------------------------------------------
-- It actually runs, and reads the metadata ORCID sends
--------------------------------------------------------------------------------
-- ORCID releases no `name` through OIDC, only given_name/family_name — a read that was
-- wrong once already (fixed and backfilled in 20260720010000). The composed form is
-- asserted here so it cannot regress silently a second time.
insert into auth.users (
	instance_id, id, aud, role, email,
	encrypted_password, email_confirmed_at,
	raw_app_meta_data, raw_user_meta_data,
	created_at, updated_at,
	confirmation_token, recovery_token, email_change_token_new, email_change
) values (
	'00000000-0000-0000-0000-000000000000',
	'11111111-1111-1111-1111-111111111111',
	'authenticated', 'authenticated', 'orcid_signup@test.local',
	'', now(),
	'{"provider":"custom:orcid","providers":["custom:orcid"]}',
	'{"sub":"0009-0001-0000-0001","given_name":"Ada","family_name":"Lovelace"}',
	now(), now(),
	'', '', '', ''
);

select is(
	(select count(*)::int from public.scholars where id = '11111111-1111-1111-1111-111111111111'),
	1,
	'inserting an auth user creates the scholar row'
);

select is(
	(select orcid from public.scholars where id = '11111111-1111-1111-1111-111111111111'),
	'0009-0001-0000-0001',
	'the ORCID iD comes from the OIDC sub claim'
);

select is(
	(select name from public.scholars where id = '11111111-1111-1111-1111-111111111111'),
	'Ada Lovelace',
	'the name is composed from given_name and family_name'
);

-- A provider that sends `name` outright wins over the composed form.
insert into auth.users (
	instance_id, id, aud, role, email,
	encrypted_password, email_confirmed_at,
	raw_app_meta_data, raw_user_meta_data,
	created_at, updated_at,
	confirmation_token, recovery_token, email_change_token_new, email_change
) values (
	'00000000-0000-0000-0000-000000000000',
	'22222222-2222-2222-2222-222222222222',
	'authenticated', 'authenticated', 'named_signup@test.local',
	'', now(),
	'{"provider":"custom:orcid","providers":["custom:orcid"]}',
	'{"sub":"0009-0001-0000-0002","name":"Grace Hopper","given_name":"Grace","family_name":"Hopper"}',
	now(), now(),
	'', '', '', ''
);

select is(
	(select name from public.scholars where id = '22222222-2222-2222-2222-222222222222'),
	'Grace Hopper',
	'an explicit name is preferred over the composed one'
);

-- The contact email is app-level and verified separately (#27); the trigger must never
-- seed it from the auth identity, or scholars.email would hold unverified addresses.
select is(
	(select email from public.scholars where id = '11111111-1111-1111-1111-111111111111'),
	null,
	'the trigger does not copy an email onto the scholar'
);

--------------------------------------------------------------------------------
-- Nothing else can create one
--------------------------------------------------------------------------------
select tests.authenticate_as('11111111-1111-1111-1111-111111111111');
select throws_ok(
	$$ insert into public.scholars (id, name) values (gen_random_uuid(), 'Imposter') $$,
	'42501',
	null,
	'an authenticated scholar cannot insert a scholar row'
);

select * from finish();
rollback;
