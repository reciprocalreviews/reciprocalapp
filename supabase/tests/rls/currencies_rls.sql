-- RLS tests for public.currencies.
--
-- Authorization model under test:
--   SELECT  public — any authenticated scholar or anonymous visitor.
--   INSERT  stewards only (the issteward() WITH CHECK).
--   UPDATE  minters of the currency only (USING auth.uid() = any(minters)).
--   DELETE  minters of the currency only (USING auth.uid() = any(minters)).
--   TRIGGER no_admin_minters (BEFORE UPDATE): a minter of a currency may not be
--           an admin of any venue that uses the currency.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();
select tests.create_scholar('cur_minter@test.local') as minter \gset
select tests.create_scholar('cur_steward@test.local', true) as steward \gset
select tests.create_scholar('cur_outsider@test.local') as outsider \gset
select tests.create_scholar('cur_vadmin@test.local') as vadmin \gset

-- The currency under test, minted by :minter.
select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
-- A venue that uses the currency, administered by a DISTINCT scholar (:vadmin),
-- so the no_minter_admins / no_admin_minters constraint holds at creation time.
select tests.create_venue(:'cur', array[:'vadmin']::uuid[]) as ven \gset

-- A second, independent currency used for the delete tests so the update tests
-- above don't interfere with row state.
select tests.create_currency(array[:'minter']::uuid[]) as cur_del \gset

-- ---- Policy shape -------------------------------------------------------------
select policies_are(
	'public', 'currencies',
	array[
		'only stewards can create currencies',
		'anyone can view currencies',
		'minters can delete currencies',
		'minters can update currencies'
	]
);

-- ---- SELECT (public) ----------------------------------------------------------
select tests.authenticate_as(:'minter');
select isnt_empty(
	$$ select 1 from public.currencies where id = $$ || quote_literal(:'cur'),
	'a minter can view the currency'
);

select tests.authenticate_as(:'outsider');
select isnt_empty(
	$$ select 1 from public.currencies where id = $$ || quote_literal(:'cur'),
	'any authenticated scholar can view the currency'
);

select tests.authenticate_as_anon();
select isnt_empty(
	$$ select 1 from public.currencies where id = $$ || quote_literal(:'cur'),
	'an anonymous visitor can view the currency'
);

-- ---- INSERT (stewards only) ---------------------------------------------------
-- A steward may create a currency.
select tests.authenticate_as(:'steward');
select lives_ok(
	$$ insert into public.currencies (name, minters)
	   values ('Steward Currency', array[ $$ || quote_literal(:'steward') || $$ ]::uuid[]) $$,
	'a steward can create a currency'
);

-- A non-steward is denied by the WITH CHECK.
select tests.authenticate_as(:'outsider');
select throws_ok(
	$$ insert into public.currencies (name, minters)
	   values ('Sneaky Currency', array[ $$ || quote_literal(:'outsider') || $$ ]::uuid[]) $$,
	'42501',
	null,
	'a non-steward cannot create a currency'
);

-- ---- UPDATE (minters only) ----------------------------------------------------
-- A minter can update their currency.
select tests.authenticate_as(:'minter');
select lives_ok(
	$$ update public.currencies set name = 'Renamed' where id = $$ || quote_literal(:'cur'),
	'a minter can update their currency'
);
select tests.clear_authentication();
select is(
	(select name from public.currencies where id = :'cur'),
	'Renamed',
	'the currency was renamed by its minter'
);

-- A non-minter's UPDATE is filtered by the USING clause (0 rows, no error).
select tests.authenticate_as(:'outsider');
update public.currencies set name = 'Hijacked' where id = :'cur';
select tests.clear_authentication();
select is(
	(select name from public.currencies where id = :'cur'),
	'Renamed',
	'a non-minter cannot update the currency (no-op)'
);

-- ---- UPDATE trigger: no_admin_minters -----------------------------------------
-- A minter may not become an admin of a venue using the currency. :vadmin admins
-- the venue, so adding :vadmin to minters must raise from the trigger.
select tests.authenticate_as(:'minter');
select throws_ok(
	$$ update public.currencies
	   set minters = array[ $$ || quote_literal(:'minter') || $$, $$ || quote_literal(:'vadmin') || $$ ]::uuid[]
	   where id = $$ || quote_literal(:'cur'),
	'P0001',
	'A venue minter cannot be the admin of the venue currency',
	'a venue admin cannot be added as a minter of the venue currency'
);

-- ---- DELETE (minters only) ----------------------------------------------------
-- A non-minter's DELETE is filtered by the USING clause (0 rows, no error).
select tests.authenticate_as(:'outsider');
delete from public.currencies where id = :'cur_del';
select tests.clear_authentication();
select is(
	(select count(*)::int from public.currencies where id = :'cur_del'),
	1,
	'a non-minter cannot delete the currency'
);

-- A minter can delete their currency.
select tests.authenticate_as(:'minter');
select lives_ok(
	$$ delete from public.currencies where id = $$ || quote_literal(:'cur_del'),
	'a minter can delete their currency'
);

select * from finish();
rollback;
