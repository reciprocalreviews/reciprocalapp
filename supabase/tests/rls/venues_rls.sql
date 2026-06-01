-- RLS tests for public.venues.
--
-- Authorization model under test:
--   SELECT  anyone (authenticated + anon).
--   INSERT  stewards only.
--   UPDATE  stewards or the venue's own admins.
--   DELETE  stewards or the venue's own admins.
--   TRIGGER no_minter_admins: a venue admin may not be a minter of the venue's
--           currency; the trigger raises on both INSERT and UPDATE.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(13);

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();
select tests.create_scholar('ven_steward@test.local', true) as steward \gset
select tests.create_scholar('ven_minter@test.local') as minter \gset
select tests.create_scholar('ven_admin@test.local') as admin \gset
select tests.create_scholar('ven_admin2@test.local') as admin2 \gset
select tests.create_scholar('ven_outsider@test.local') as outsider \gset
-- Currency minters and venue admins must be DISTINCT (no_minter_admins trigger).
select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as ven \gset
-- A second venue used for the delete tests so the update probes keep a row.
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as ven_del \gset

-- ---- Policy shape -------------------------------------------------------------
select policies_are(
	'public', 'venues',
	array[
		'anyone can view venues',
		'only stewards can create venues',
		'stewards and admins can update venues',
		'stewards and admins can delete venues'
	]
);

-- ---- SELECT -------------------------------------------------------------------
select tests.authenticate_as(:'outsider');
select isnt_empty(
	$$ select 1 from public.venues where id = $$ || quote_literal(:'ven'),
	'any authenticated scholar can view a venue'
);

select tests.authenticate_as_anon();
select isnt_empty(
	$$ select 1 from public.venues where id = $$ || quote_literal(:'ven'),
	'anonymous visitors can view a venue'
);

-- ---- INSERT -------------------------------------------------------------------
-- A steward may create a venue (admins must not overlap currency minters).
select tests.authenticate_as(:'steward');
select lives_ok(
	$$ insert into public.venues (title, currency, welcome_amount, admins, inactive)
	   values ('Steward Venue', $$ || quote_literal(:'cur') || $$, 0,
	           array[ $$ || quote_literal(:'admin') || $$ ]::uuid[], null) $$,
	'a steward can create a venue'
);

-- A non-steward cannot create a venue (insert WITH CHECK denies → 42501).
select tests.authenticate_as(:'outsider');
select throws_ok(
	$$ insert into public.venues (title, currency, welcome_amount, admins, inactive)
	   values ('Outsider Venue', $$ || quote_literal(:'cur') || $$, 0,
	           array[ $$ || quote_literal(:'admin') || $$ ]::uuid[], null) $$,
	'42501',
	null,
	'a non-steward cannot create a venue'
);

-- ---- UPDATE -------------------------------------------------------------------
-- A steward may update any venue.
select tests.authenticate_as(:'steward');
select lives_ok(
	$$ update public.venues set title = 'Steward Updated' where id = $$ || quote_literal(:'ven'),
	'a steward can update a venue'
);

-- The venue's own admin may update it.
select tests.authenticate_as(:'admin');
select lives_ok(
	$$ update public.venues set title = 'Admin Updated' where id = $$ || quote_literal(:'ven'),
	'a venue admin can update their venue'
);

-- An unrelated scholar's UPDATE is filtered by the using clause (0 rows, no error).
select tests.authenticate_as(:'outsider');
update public.venues set title = 'Outsider Updated' where id = :'ven';
select tests.clear_authentication();
select is(
	(select title from public.venues where id = :'ven'),
	'Admin Updated',
	'a non-steward non-admin cannot update a venue (no-op)'
);

-- ---- DELETE -------------------------------------------------------------------
-- An unrelated scholar's DELETE is filtered by the using clause (0 rows, no error).
select tests.authenticate_as(:'outsider');
delete from public.venues where id = :'ven_del';
select tests.clear_authentication();
select is(
	(select count(*)::int from public.venues where id = :'ven_del'),
	1,
	'a non-steward non-admin cannot delete a venue'
);

-- The venue's own admin may delete it.
select tests.authenticate_as(:'admin');
select lives_ok(
	$$ delete from public.venues where id = $$ || quote_literal(:'ven_del'),
	'a venue admin can delete their venue'
);

-- A steward may delete any venue.
select tests.authenticate_as(:'steward');
select lives_ok(
	$$ delete from public.venues where id = $$ || quote_literal(:'ven'),
	'a steward can delete a venue'
);

-- ---- TRIGGER: no_minter_admins ------------------------------------------------
-- Inserting a venue whose admin is also a minter of its currency raises.
select tests.authenticate_as(:'steward');
select throws_ok(
	$$ insert into public.venues (title, currency, welcome_amount, admins, inactive)
	   values ('Bad Venue', $$ || quote_literal(:'cur') || $$, 0,
	           array[ $$ || quote_literal(:'minter') || $$ ]::uuid[], null) $$,
	null,
	'A venue admin cannot be the minter of the venue currency',
	'a venue admin cannot be a minter of the currency (insert)'
);

-- Updating a venue to add a minter as an admin raises.
-- Create a clean target venue in owner context (admins distinct from minters).
select tests.clear_authentication();
select tests.create_venue(:'cur', array[:'admin2']::uuid[]) as ven_trig \gset
select tests.authenticate_as(:'steward');
select throws_ok(
	$$ update public.venues set admins = array[ $$ || quote_literal(:'minter') || $$ ]::uuid[]
	   where id = $$ || quote_literal(:'ven_trig'),
	null,
	'A venue admin cannot be the minter of the venue currency',
	'a venue admin cannot be a minter of the currency (update)'
);

select * from finish();
rollback;
