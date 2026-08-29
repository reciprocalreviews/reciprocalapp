-- Who may see another scholar's balance: public.can_see_balances and the two
-- RPCs that depend on it.
--
-- #109 resolved: balances are not public. The audience is the holder, the people
-- holding roles involved in bidding at a venue using that currency, and that
-- currency's minters.
--
-- WHY THE RULE IS HERE RATHER THAN IN THE POLICY
--
-- A policy is evaluated once PER ROW, and public.tokens has one row per token, so
-- a reserve holding a community's supply would pay for the audience test a
-- quarter of a million times. The tokens policy therefore answers only what a
-- per-row test must -- is this row mine, or a venue's -- and every cross-scholar
-- read goes through scholar_balances, which asks can_see_balances ONCE per call.
-- tokens_rls.sql asserts the table side; this file asserts the RPC side. Neither
-- is meaningful without the other.
begin;

\ir ../_helpers/helpers.sql.inc
select plan(12);

--------------------------------------------------------------------------------
-- Fixtures: one currency, one venue on it, and a second venue on a DIFFERENT
-- currency, so the tests can prove the audience is currency-scoped rather than
-- "anyone who volunteers anywhere".
--------------------------------------------------------------------------------
select tests.clear_authentication();
select tests.create_scholar('bp_holder@test.local') as holder \gset
select tests.create_scholar('bp_minter@test.local') as minter \gset
select tests.create_scholar('bp_admin@test.local') as vadmin \gset
select tests.create_scholar('bp_reviewer@test.local') as reviewer \gset
select tests.create_scholar('bp_quit@test.local') as quitter \gset
select tests.create_scholar('bp_elsewhere@test.local') as elsewhere \gset
select tests.create_scholar('bp_nobody@test.local') as nobody \gset

select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'vadmin']::uuid[]) as ven \gset
select tests.create_role(:'ven', 0) as role \gset
select tests.create_volunteer(:'reviewer', :'role') as vol \gset

-- A volunteer who stepped down. The row survives on purpose (it is what stops a
-- welcome grant being made twice), so `accepted` alone would leave visibility
-- behind forever -- can_see_balances requires `active` as well.
select tests.create_volunteer(:'quitter', :'role') as vol_quit \gset
update public.volunteers set active = false where id = :'vol_quit';

-- An accepted, active volunteer at a venue on a DIFFERENT currency.
select tests.create_currency(array[:'minter']::uuid[]) as other_cur \gset
select tests.create_venue(:'other_cur', array[:'nobody']::uuid[]) as other_ven \gset
select tests.create_role(:'other_ven', 0) as other_role \gset
select tests.create_volunteer(:'elsewhere', :'other_role') as vol_elsewhere \gset

-- Nine tokens for the holder, in the currency under test.
insert into public.tokens (currency, scholar)
select :'cur', :'holder' from generate_series(1, 9);

create or replace function pg_temp.balance_rows (p_viewer uuid) returns bigint language plpgsql as $$
declare _n bigint;
begin
	perform tests.authenticate_as(p_viewer);
	select count(*) into _n from public.scholar_balances(
		(select id from public.currencies where id = current_setting('pg_temp.cur')::uuid),
		array[current_setting('pg_temp.holder')::uuid]
	);
	return _n;
end;
$$;

select set_config('pg_temp.cur', :'cur', false);
select set_config('pg_temp.holder', :'holder', false);

--------------------------------------------------------------------------------
-- In the audience.
--------------------------------------------------------------------------------
select tests.authenticate_as(:'vadmin');
select ok(public.can_see_balances(:'cur'), 'a venue admin on this currency is in the audience');

select tests.authenticate_as(:'reviewer');
select ok(public.can_see_balances(:'cur'), 'an accepted active volunteer is in the audience');

select tests.authenticate_as(:'minter');
select ok(public.can_see_balances(:'cur'), 'a minter of the currency is in the audience');

--------------------------------------------------------------------------------
-- Out of it.
--------------------------------------------------------------------------------
select tests.authenticate_as(:'nobody');
select ok(not public.can_see_balances(:'cur'), 'an unaffiliated scholar is not in the audience');

select tests.authenticate_as(:'quitter');
select ok(
	not public.can_see_balances(:'cur'),
	'a volunteer who stepped down loses the audience -- the row survives, the access does not'
);

select tests.authenticate_as(:'elsewhere');
select ok(
	not public.can_see_balances(:'cur'),
	'volunteering at a venue on another currency confers nothing here'
);

select tests.authenticate_as(:'holder');
select ok(
	not public.can_see_balances(:'cur'),
	'holding tokens does not put you in the audience for everyone else''s'
);

--------------------------------------------------------------------------------
-- scholar_balances honours it, and always returns you your own row.
--------------------------------------------------------------------------------
select is(pg_temp.balance_rows(:'vadmin'), 1::bigint, 'a venue admin gets the holder''s balance');
select is(pg_temp.balance_rows(:'nobody'), 0::bigint, 'an outsider gets nothing back');
select is(pg_temp.balance_rows(:'holder'), 1::bigint, 'the holder always gets their own row');

--------------------------------------------------------------------------------
-- authors_can_cover answers can/cannot without disclosing an amount. It is
-- deliberately NOT gated: a submitter must be told which co-authors cannot pay,
-- or a co-authored submission fails at create_submission with an RR003 nobody can
-- act on. A yes/no about a charge the submitter is themselves proposing is a far
-- smaller disclosure than a balance.
--------------------------------------------------------------------------------
select tests.authenticate_as(:'nobody');
select results_eq(
	$$ select covered from public.authors_can_cover(
		current_setting('pg_temp.cur')::uuid,
		array[current_setting('pg_temp.holder')::uuid],
		array[9]) $$,
	$$ values (true) $$,
	'an outsider learns a co-author CAN cover exactly their charge'
);
select results_eq(
	$$ select covered from public.authors_can_cover(
		current_setting('pg_temp.cur')::uuid,
		array[current_setting('pg_temp.holder')::uuid],
		array[10]) $$,
	$$ values (false) $$,
	'and CANNOT cover one token more -- a boolean, never the balance itself'
);

select * from finish();

rollback;
