-- Tests for ensure_scholar, defined in migration 20260901000000_ensure_scholar.sql.
--
-- The repair path for an account with no scholar row. Because a scholar row is created
-- once — by the on_auth_user_created trigger, at signup — an account that misses it can
-- never recover on its own: the session stays valid, so signing in again does not
-- re-create the auth user and the trigger never fires a second time.
--
-- The function is SECURITY DEFINER, so it reaches past the `with check (false)` INSERT
-- policy that otherwise forbids creating a scholar row at all. That makes its blast
-- radius the thing worth testing: it takes NO arguments, and the row it creates is
-- always auth.uid()'s, so there is no way to aim it at another scholar. These tests are
-- the safety net for that, and for the deliberate choice to report an ORCID collision
-- rather than resolve it.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(11);

-- ---- Fixtures (owner context) ------------------------------------------------
select tests.clear_authentication();
select tests.create_scholar('present@test.local') as present \gset

-- An account with no scholar row: created the way a signup does, then the row removed,
-- which is exactly the state the production incident left behind.
select tests.create_scholar('orphan@test.local') as orphan \gset
delete from public.scholars where id = :'orphan';

--------------------------------------------------------------------------------
-- Authorization
--------------------------------------------------------------------------------
-- EXECUTE is revoked from anon, so this fails on privilege before the body runs.
select tests.authenticate_as_anon();
select throws_ok(
	$$ select public.ensure_scholar() $$,
	'42501',
	null,
	'an anonymous visitor cannot execute ensure_scholar'
);

--------------------------------------------------------------------------------
-- The ordinary case: nothing to do
--------------------------------------------------------------------------------
select tests.authenticate_as(:'present');
select is(
	public.ensure_scholar(), 'exists',
	'a scholar who already has a row is told so'
);

select is(
	(select count(*)::int from public.scholars where id = :'present'),
	1,
	'and no second row is created'
);

-- Idempotent: the layout calls this on every load where the row looks missing, and a
-- misread must not accumulate writes.
select is(
	public.ensure_scholar(), 'exists',
	'calling it again is still a no-op'
);

--------------------------------------------------------------------------------
-- The repair
--------------------------------------------------------------------------------
select tests.authenticate_as(:'orphan');
select is(
	public.ensure_scholar(), 'created',
	'an account with no scholar row gets one'
);

select is(
	(select count(*)::int from public.scholars where id = :'orphan'),
	1,
	'and the row is the caller''s own'
);

-- The fixture's auth user carries '{}' metadata, so there is no iD to recover. Null is
-- the honest answer; a placeholder would be worse, since orcid is the identity anchor.
select is(
	(select orcid from public.scholars where id = :'orphan'),
	null,
	'with no OIDC metadata, the iD is left null rather than invented'
);

select is(
	public.ensure_scholar(), 'exists',
	'a second call after the repair does nothing'
);

--------------------------------------------------------------------------------
-- It only ever touches the caller's own row
--------------------------------------------------------------------------------
-- The strongest property here: another orphan's row stays missing no matter who calls,
-- because the function reads auth.uid() and accepts nothing from the caller.
select tests.clear_authentication();
select tests.create_scholar('other@test.local') as other \gset
delete from public.scholars where id = :'other';

select tests.authenticate_as(:'present');
select ensure_scholar();
select is(
	(select count(*)::int from public.scholars where id = :'other'),
	0,
	'calling it does not create a row for anyone else'
);

--------------------------------------------------------------------------------
-- An ORCID collision is reported, not resolved
--------------------------------------------------------------------------------
-- scholars_orcid_unique (#87): one iD, one scholar. Two accounts claiming one
-- researcher needs a person, so the function says so rather than failing the sign-in or
-- creating a row with a blank iD.
select tests.clear_authentication();
update public.scholars set orcid = '0009-0003-1111-2222' where id = :'present';
update auth.users
set raw_user_meta_data = '{"sub":"0009-0003-1111-2222"}'::jsonb
where id = :'other';

select tests.authenticate_as(:'other');
select is(
	public.ensure_scholar(), 'orcid_conflict',
	'an iD already held by another scholar is reported'
);

select is(
	(select count(*)::int from public.scholars where id = :'other'),
	0,
	'and no row is created for the colliding account'
);

select * from finish();
rollback;
