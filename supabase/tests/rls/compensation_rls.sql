-- RLS tests for public.compensation.
--
-- Authorization model under test:
--   SELECT  authenticated scholars only (any signed-in scholar) — anonymous
--           visitors cannot read compensation at all.
--   INSERT  venue admins only, where the venue is the one owning the role
--           (isAdmin((select venueid from roles where id = compensation.role))).
--   UPDATE  same: venue admins of the role's venue.
--   DELETE  same: venue admins of the role's venue.
--
-- compensation's PK is (submission_type, role); a fixture therefore needs a
-- venue, a submission_type at that venue, and a role at that venue.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();
-- Distinct scholars for admin vs minter (no_minter_admins / no_admin_minters).
select tests.create_scholar('comp_minter@test.local') as minter \gset
select tests.create_scholar('comp_vadmin@test.local') as vadmin \gset
select tests.create_scholar('comp_other_admin@test.local') as oadmin \gset
select tests.create_scholar('comp_reader@test.local') as reader \gset
select tests.create_scholar('comp_outsider@test.local') as outsider \gset

-- Currency + the venue under test (vadmin is its admin).
select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'vadmin']::uuid[]) as ven \gset
-- A second, unrelated venue with a DIFFERENT admin (oadmin), same currency.
select tests.create_venue(:'cur', array[:'oadmin']::uuid[]) as ven2 \gset

-- A role + submission_type at the venue under test.
select tests.create_role(:'ven') as role \gset
select tests.create_submission_type(:'ven') as stype \gset
-- A second submission_type at the venue under test (for the INSERT positive case).
select tests.create_submission_type(:'ven') as stype2 \gset

-- A seed compensation row (the role belongs to ven, owned by vadmin).
insert into public.compensation (submission_type, role, amount, rationale)
values (:'stype', :'role', 100, 'seed');

-- ---- Policy shape -------------------------------------------------------------
select policies_are(
	'public', 'compensation',
	array[
		'venue admins can insert compensation',
		'authenticated scholars can read compensation',
		'venue admins can update compensation',
		'venue admins can delete compensation'
	]
);

-- ---- SELECT -------------------------------------------------------------------
-- Any authenticated scholar may read compensation, related or not.
select tests.authenticate_as(:'reader');
select isnt_empty(
	$$ select 1 from public.compensation where submission_type = $$ || quote_literal(:'stype') ||
	$$ and role = $$ || quote_literal(:'role'),
	'an authenticated scholar can read compensation'
);

select tests.authenticate_as(:'vadmin');
select isnt_empty(
	$$ select 1 from public.compensation where submission_type = $$ || quote_literal(:'stype') ||
	$$ and role = $$ || quote_literal(:'role'),
	'a venue admin can read compensation'
);

-- Anonymous visitors cannot read compensation.
select tests.authenticate_as_anon();
select is_empty(
	$$ select 1 from public.compensation where submission_type = $$ || quote_literal(:'stype') ||
	$$ and role = $$ || quote_literal(:'role'),
	'anonymous visitors cannot read compensation'
);

-- ---- INSERT -------------------------------------------------------------------
-- The role's venue admin may insert compensation for that role.
select tests.authenticate_as(:'vadmin');
select lives_ok(
	$$ insert into public.compensation (submission_type, role, amount, rationale)
	   values ( $$ || quote_literal(:'stype2') || $$, $$ || quote_literal(:'role') || $$, 50, 'admin add') $$,
	'a venue admin can insert compensation for a role in their venue'
);

-- An admin of a DIFFERENT venue cannot insert compensation for this role.
select tests.authenticate_as(:'oadmin');
select throws_ok(
	$$ insert into public.compensation (submission_type, role, amount, rationale)
	   values ( $$ || quote_literal(:'stype') || $$, $$ || quote_literal(:'role') || $$, 999, 'foreign admin') $$,
	'42501',
	null,
	'an admin of another venue cannot insert compensation for this role'
);

-- A non-admin scholar cannot insert compensation.
select tests.authenticate_as(:'outsider');
select throws_ok(
	$$ insert into public.compensation (submission_type, role, amount, rationale)
	   values ( $$ || quote_literal(:'stype') || $$, $$ || quote_literal(:'role') || $$, 999, 'outsider') $$,
	'42501',
	null,
	'a non-admin scholar cannot insert compensation'
);

-- ---- UPDATE -------------------------------------------------------------------
-- The role's venue admin may update compensation.
select tests.authenticate_as(:'vadmin');
select lives_ok(
	$$ update public.compensation set amount = 200 where submission_type = $$ || quote_literal(:'stype') ||
	$$ and role = $$ || quote_literal(:'role'),
	'a venue admin can update compensation for a role in their venue'
);
select tests.clear_authentication();
select is(
	(select amount from public.compensation where submission_type = :'stype' and role = :'role'),
	200,
	'the compensation amount is now updated'
);

-- An admin of another venue cannot update this role's compensation. The update
-- is filtered by the using clause (0 rows, no error); the row is unchanged.
select tests.authenticate_as(:'oadmin');
update public.compensation set amount = 7 where submission_type = :'stype' and role = :'role';
select tests.clear_authentication();
select is(
	(select amount from public.compensation where submission_type = :'stype' and role = :'role'),
	200,
	'an admin of another venue cannot update this role''s compensation (no-op)'
);

-- A non-admin scholar's update is filtered out (0 rows, no error); unchanged.
select tests.authenticate_as(:'outsider');
update public.compensation set amount = 9 where submission_type = :'stype' and role = :'role';
select tests.clear_authentication();
select is(
	(select amount from public.compensation where submission_type = :'stype' and role = :'role'),
	200,
	'a non-admin scholar cannot update compensation (no-op)'
);

-- ---- DELETE -------------------------------------------------------------------
-- An admin of another venue cannot delete this role's compensation (using
-- filters the row → 0 rows, no error); the row is still present.
select tests.authenticate_as(:'oadmin');
delete from public.compensation where submission_type = :'stype' and role = :'role';
select tests.clear_authentication();
select is(
	(select count(*)::int from public.compensation where submission_type = :'stype' and role = :'role'),
	1,
	'an admin of another venue cannot delete this role''s compensation'
);

-- A non-admin scholar cannot delete (using filters the row → 0 rows, no error).
select tests.authenticate_as(:'outsider');
delete from public.compensation where submission_type = :'stype' and role = :'role';
select tests.clear_authentication();
select is(
	(select count(*)::int from public.compensation where submission_type = :'stype' and role = :'role'),
	1,
	'a non-admin scholar cannot delete compensation'
);

-- The role's venue admin can delete compensation for that role.
select tests.authenticate_as(:'vadmin');
select lives_ok(
	$$ delete from public.compensation where submission_type = $$ || quote_literal(:'stype') ||
	$$ and role = $$ || quote_literal(:'role'),
	'a venue admin can delete compensation for a role in their venue'
);

select * from finish();
rollback;
