-- RLS tests for public.venues.
--
-- Authorization model under test:
--   SELECT  anyone (authenticated + anon).
--   INSERT  stewards only.
--   UPDATE  stewards or the venue's own admins.
--   DELETE  no one (denied by policy AND the table privilege is revoked, since
--           deletion would cascade away roles, volunteers, assignments,
--           compensation, preference levels, and thanks).
--   ADMIN/MINTER OVERLAP: a venue admin may also mint the venue's
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
-- Currency minters and venue admins are kept DISTINCT here, so these cases exercise
-- the ordinary arrangement rather than the overlap tested at the end of the file.
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
		'venues cannot be deleted'
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
-- The table privilege is revoked, so every client DELETE fails with 42501 —
-- an unrelated scholar, the venue's own admin, and a steward alike.
select tests.authenticate_as(:'outsider');
select throws_ok(
	$$ delete from public.venues where id = $$ || quote_literal(:'ven_del'),
	'42501',
	null,
	'a non-steward non-admin cannot delete a venue'
);

select tests.authenticate_as(:'admin');
select throws_ok(
	$$ delete from public.venues where id = $$ || quote_literal(:'ven_del'),
	'42501',
	null,
	'a venue admin cannot delete their venue'
);

select tests.authenticate_as(:'steward');
select throws_ok(
	$$ delete from public.venues where id = $$ || quote_literal(:'ven'),
	'42501',
	null,
	'a steward cannot delete a venue'
);

-- ---- ADMIN/MINTER OVERLAP: permitted, not refused -----------------------------
-- The `no_minter_admins` trigger used to refuse an active venue whose admin minted its
-- currency. It is gone: a small community's organizer is often its only minter, and the
-- venue page discloses the arrangement instead. Both writes it blocked must now succeed.
--
-- Creating an ACTIVE venue (inactive is null) whose admin mints its currency.
select tests.authenticate_as(:'steward');
select lives_ok(
	$$ insert into public.venues (title, currency, welcome_amount, admins, inactive)
	   values ('Solo Venue', $$ || quote_literal(:'cur') || $$, 0,
	           array[ $$ || quote_literal(:'minter') || $$ ]::uuid[], null) $$,
	'an active venue may be administered by a minter of its currency (insert)'
);

-- Handing an already-live venue to an admin who mints its currency.
-- Create a clean target venue in owner context (admins distinct from minters).
select tests.clear_authentication();
select tests.create_venue(:'cur', array[:'admin2']::uuid[]) as ven_trig \gset
select tests.authenticate_as(:'steward');
select lives_ok(
	$$ update public.venues set admins = array[ $$ || quote_literal(:'minter') || $$ ]::uuid[]
	   where id = $$ || quote_literal(:'ven_trig'),
	'a venue may take on an admin who mints its currency (update)'
);

select * from finish();
rollback;
