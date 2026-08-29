-- _move_tokens: the single path by which existing value changes hands.
--
-- WHAT THIS IS PROTECTING
--
-- Six RPCs used to pick tokens with `select id from tokens where <holder> order
-- by id limit N` and then move them with `update ... where id = any(_token_ids)`
-- -- no lock on the select, no ownership predicate on the update. Under READ
-- COMMITTED two concurrent draws on one holder select THE SAME ROWS, because the
-- order is `id` and therefore deterministic. The second update blocks on the
-- first's row locks and then, since `id = any(...)` is still true once the first
-- commits, overwrites them. Both callers report success and both write a
-- transactions row, but the first recipient's tokens are gone. The holder's
-- count(*) stays consistent, which is exactly why nothing noticed -- only
-- reconcile_ledger's conservation check would have caught it, a day later.
--
-- Reproduced before the fix, with a 50-token reserve and two sessions each
-- drawing 25: both reported moving 25, and the first scholar ended up holding 0.
--
-- WHY THE RACE ITSELF IS NOT ONE OF THE CASES BELOW
--
-- pgTAP runs each file in a single transaction that is rolled back, and the only
-- way to get a second session (dblink) opens a separate connection that sees
-- only COMMITTED rows -- so it cannot see the fixtures this file creates. What is
-- testable here is the contract the lock exists to keep, plus the presence of
-- the lock itself, which is asserted structurally at the end. Treat that last
-- test as load-bearing: it is what fails if someone "simplifies" the two
-- branches back into one OR'd predicate and drops the clause along the way.
begin;

\ir ../_helpers/helpers.sql.inc
select plan(15);

--------------------------------------------------------------------------------
-- Fixtures: one currency, one venue reserve, two scholars to pay.
--------------------------------------------------------------------------------
create temporary table ids (name text primary key, id uuid);

insert into ids (name, id)
values
	('minter', tests.create_scholar('minter@uni.edu')),
	('admin', tests.create_scholar('admin@uni.edu')),
	('alice', tests.create_scholar('alice@uni.edu')),
	('bob', tests.create_scholar('bob@uni.edu'));

create or replace function pg_temp.id (p_name text) returns uuid language sql as $$
	select id from ids where name = p_name;
$$;

insert into ids (name, id)
values ('currency', tests.create_currency(array[pg_temp.id('minter')]));

insert into ids (name, id)
values ('venue', tests.create_venue(pg_temp.id('currency'), array[pg_temp.id('admin')]));

-- A second currency, so the tests can prove the currency filter is real.
insert into ids (name, id)
values ('other_currency', tests.create_currency(array[pg_temp.id('minter')]));

-- 50 tokens in the venue reserve, plus 10 of a different currency in the same
-- reserve that must never be touched.
insert into public.tokens (currency, venue, scholar)
select pg_temp.id('currency'), pg_temp.id('venue'), null from generate_series(1, 50);

insert into public.tokens (currency, venue, scholar)
select pg_temp.id('other_currency'), pg_temp.id('venue'), null from generate_series(1, 10);

create or replace function pg_temp.held_by_scholar (p_scholar text, p_currency text default 'currency')
returns bigint language sql as $$
	select count(*) from public.tokens
	where scholar = pg_temp.id(p_scholar) and currency = pg_temp.id(p_currency);
$$;

create or replace function pg_temp.held_by_venue (p_currency text default 'currency')
returns bigint language sql as $$
	select count(*) from public.tokens
	where venue = pg_temp.id('venue') and currency = pg_temp.id(p_currency);
$$;

--------------------------------------------------------------------------------
-- An ordinary draw moves exactly what was asked for, and no more.
--------------------------------------------------------------------------------
select is(
	cardinality(public._move_tokens(
		pg_temp.id('currency'), null, pg_temp.id('venue'), pg_temp.id('alice'), null,
		25, 'short'
	)),
	25,
	'a draw of 25 returns 25 token ids'
);

select is(pg_temp.held_by_scholar('alice'), 25::bigint, 'alice holds the 25 that moved');
select is(pg_temp.held_by_venue(), 25::bigint, 'the reserve is down by exactly 25');
select is(pg_temp.held_by_venue('other_currency'), 10::bigint, 'the other currency in the same reserve is untouched');

--------------------------------------------------------------------------------
-- A second draw takes DIFFERENT tokens. This is the property the lock exists to
-- guarantee under concurrency; sequentially it must hold trivially, and a
-- regression that reintroduced the overwrite would break it here too.
--------------------------------------------------------------------------------
select is(
	cardinality(public._move_tokens(
		pg_temp.id('currency'), null, pg_temp.id('venue'), pg_temp.id('bob'), null,
		25, 'short'
	)),
	25,
	'a second draw of 25 also returns 25 token ids'
);

select is(pg_temp.held_by_scholar('alice'), 25::bigint, 'alice still holds her 25 -- the second draw did not take them');
select is(pg_temp.held_by_scholar('bob'), 25::bigint, 'bob holds 25');
select is(pg_temp.held_by_venue(), 0::bigint, 'the reserve is empty, and 25 + 25 came out of 50');

--------------------------------------------------------------------------------
-- An empty reserve cannot pay, and says so with RR003 rather than paying less.
--------------------------------------------------------------------------------
select throws_ok(
	format(
		'select public._move_tokens(%L, null, %L, %L, null, 1, %L)',
		pg_temp.id('currency'), pg_temp.id('venue'), pg_temp.id('alice'), 'not enough'
	),
	'RR003',
	'not enough',
	'an exhausted reserve raises RR003 with the caller''s message'
);

--------------------------------------------------------------------------------
-- A partial shortfall is refused whole. Paying out what happens to be available
-- would leave a transaction claiming an amount that never moved.
--------------------------------------------------------------------------------
insert into public.tokens (currency, venue, scholar)
select pg_temp.id('currency'), pg_temp.id('venue'), null from generate_series(1, 3);

select throws_ok(
	format(
		'select public._move_tokens(%L, null, %L, %L, null, 5, %L)',
		pg_temp.id('currency'), pg_temp.id('venue'), pg_temp.id('alice'), 'not enough'
	),
	'RR003',
	'not enough',
	'a reserve holding 3 refuses a draw of 5 rather than moving 3'
);

select is(pg_temp.held_by_venue(), 3::bigint, 'the refused draw moved nothing');

--------------------------------------------------------------------------------
-- _mint_shortfall covers the gap instead of raising. This is the welcome-grant
-- contract: grant the stated amount, minting whatever the reserve lacks.
--------------------------------------------------------------------------------
select is(
	cardinality(public._move_tokens(
		pg_temp.id('currency'), null, pg_temp.id('venue'), pg_temp.id('bob'), null,
		5, 'short', true
	)),
	5,
	'_mint_shortfall grants the full amount from a reserve holding only 3'
);

select is(pg_temp.held_by_scholar('bob'), 30::bigint, 'bob received all 5, three drawn and two minted');

--------------------------------------------------------------------------------
-- Spending one's own balance works in the other direction too.
--------------------------------------------------------------------------------
select lives_ok(
	format(
		'select public._move_tokens(%L, %L, null, null, %L, 10, %L)',
		pg_temp.id('currency'), pg_temp.id('alice'), pg_temp.id('venue'), 'short'
	),
	'a scholar can spend their own balance back to a venue'
);

--------------------------------------------------------------------------------
-- The lock itself. Structural, because the race cannot be staged in this
-- harness -- but this is the line whose removal reintroduces the bug, so it is
-- asserted rather than assumed.
--------------------------------------------------------------------------------
select matches(
	pg_get_functiondef('public._move_tokens(uuid,uuid,uuid,uuid,uuid,integer,text,boolean)'::regprocedure),
	'for update skip locked',
	'_move_tokens still takes its rows with FOR UPDATE SKIP LOCKED'
);

select * from finish();

rollback;
