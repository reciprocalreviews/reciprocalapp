-- RLS tests for public.exchanges.
--
-- Authorization model under test:
--   SELECT  anyone (anon + authenticated) may view exchanges.
--   INSERT  only a minter of EITHER currency in the exchange (currency_from or
--           currency_to) may create it (isMinter on the with-check row).
--   UPDATE  only a minter of either currency may update (using-clause filter).
--   DELETE  only a minter of either currency may delete (using-clause filter).

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(15);

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();
select tests.create_scholar('xch_minter_from@test.local') as minter_from \gset
select tests.create_scholar('xch_minter_to@test.local') as minter_to \gset
select tests.create_scholar('xch_outsider@test.local') as outsider \gset
select tests.create_currency(array[:'minter_from']::uuid[]) as cur_from \gset
select tests.create_currency(array[:'minter_to']::uuid[]) as cur_to \gset
-- A third currency, minted by the outsider, unrelated to the exchange.
select tests.create_currency(array[:'outsider']::uuid[]) as cur_other \gset

-- An exchange between cur_from and cur_to (inserted in owner context).
insert into public.exchanges (currency_from, currency_to, ratio)
values (:'cur_from', :'cur_to', 2)
returning id as xch \gset

-- ---- Policy shape -------------------------------------------------------------
select policies_are(
	'public', 'exchanges',
	array[
		'anyone can view exchanges',
		'only minters can create exchanges',
		'only minters can update exchanges',
		'only minters can delete exchanges'
	]
);

-- ---- SELECT -------------------------------------------------------------------
select tests.authenticate_as(:'minter_from');
select isnt_empty(
	$$ select 1 from public.exchanges where id = $$ || quote_literal(:'xch'),
	'a minter of currency_from can see the exchange'
);

select tests.authenticate_as(:'outsider');
select isnt_empty(
	$$ select 1 from public.exchanges where id = $$ || quote_literal(:'xch'),
	'an unrelated authenticated scholar can see the exchange (public read)'
);

select tests.authenticate_as_anon();
select isnt_empty(
	$$ select 1 from public.exchanges where id = $$ || quote_literal(:'xch'),
	'anonymous visitors can see the exchange (public read)'
);

-- ---- INSERT -------------------------------------------------------------------
-- A minter of currency_from may create an exchange involving that currency.
select tests.authenticate_as(:'minter_from');
select lives_ok(
	$$ insert into public.exchanges (currency_from, currency_to, ratio)
	   values ( $$ || quote_literal(:'cur_other') || $$, $$ || quote_literal(:'cur_from') || $$, 3) $$,
	'a minter of currency_to can create an exchange'
);

-- A minter of currency_to may create an exchange involving that currency.
select tests.authenticate_as(:'minter_to');
select lives_ok(
	$$ insert into public.exchanges (currency_from, currency_to, ratio)
	   values ( $$ || quote_literal(:'cur_to') || $$, $$ || quote_literal(:'cur_other') || $$, 4) $$,
	'a minter of currency_from can create an exchange'
);

-- A scholar who mints neither currency cannot create an exchange between them.
select tests.authenticate_as(:'outsider');
select throws_ok(
	$$ insert into public.exchanges (currency_from, currency_to, ratio)
	   values ( $$ || quote_literal(:'cur_from') || $$, $$ || quote_literal(:'cur_to') || $$, 5) $$,
	'42501',
	null,
	'a non-minter of either currency cannot create an exchange'
);

-- An anonymous visitor cannot create an exchange (policy is authenticated-only).
select tests.authenticate_as_anon();
select throws_ok(
	$$ insert into public.exchanges (currency_from, currency_to, ratio)
	   values ( $$ || quote_literal(:'cur_from') || $$, $$ || quote_literal(:'cur_to') || $$, 6) $$,
	'42501',
	null,
	'an anonymous visitor cannot create an exchange'
);

-- ---- UPDATE -------------------------------------------------------------------
-- A minter of currency_from may update the exchange.
select tests.authenticate_as(:'minter_from');
select lives_ok(
	$$ update public.exchanges set ratio = 7 where id = $$ || quote_literal(:'xch'),
	'a minter of currency_from can update the exchange'
);
select tests.clear_authentication();
select is(
	(select ratio from public.exchanges where id = :'xch'),
	7::numeric,
	'the exchange ratio was updated by the minter'
);

-- A minter of currency_to may update the exchange.
select tests.authenticate_as(:'minter_to');
select lives_ok(
	$$ update public.exchanges set ratio = 8 where id = $$ || quote_literal(:'xch'),
	'a minter of currency_to can update the exchange'
);

-- A non-minter's UPDATE is filtered by the using clause (0 rows, no error).
select tests.authenticate_as(:'outsider');
update public.exchanges set ratio = 99 where id = :'xch';
select tests.clear_authentication();
select is(
	(select ratio from public.exchanges where id = :'xch'),
	8::numeric,
	'a non-minter cannot update the exchange (no-op)'
);

-- ---- DELETE -------------------------------------------------------------------
-- A non-minter cannot delete (using = minters only → 0 rows, no error).
select tests.authenticate_as(:'outsider');
delete from public.exchanges where id = :'xch';
select tests.clear_authentication();
select is(
	(select count(*)::int from public.exchanges where id = :'xch'),
	1,
	'a non-minter cannot delete the exchange'
);

-- A minter of currency_to can delete the exchange.
select tests.authenticate_as(:'minter_to');
select lives_ok(
	$$ delete from public.exchanges where id = $$ || quote_literal(:'xch'),
	'a minter of currency_to can delete the exchange'
);
select tests.clear_authentication();
select is(
	(select count(*)::int from public.exchanges where id = :'xch'),
	0,
	'the exchange was deleted by the minter'
);

select * from finish();
rollback;
