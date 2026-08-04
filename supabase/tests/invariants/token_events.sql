-- Behavioural tests for the token ledger.
--
-- These are the properties the whole design rests on, and each one is checked
-- against real RPC calls rather than hand-written log rows:
--
--   1. Every ownership change is captured, including one that bypasses the RPCs.
--   2. Movements caused by an RPC carry the transaction that caused them.
--   3. Movements NOT caused by an RPC are visibly unattributed — the alarm.
--   4. The log reconstructs current state exactly (tokens_as_of).
--   5. The per-token chain is continuous, so a gap is detectable.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(10);

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();
select tests.create_scholar('tev_minter@test.local') as minter \gset
select tests.create_scholar('tev_admin@test.local') as admin \gset
select tests.create_scholar('tev_alice@test.local') as alice \gset
select tests.create_scholar('tev_bob@test.local') as bob \gset

-- Minter and admin are disjoint so the no_minter_admins trigger stays quiet.
select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as ven \gset

-- ---- 1. An RPC mint is captured and attributed --------------------------------
select tests.authenticate_as(:'minter');
select lives_ok(
	$$ select public.mint_tokens( $$ || quote_literal(:'cur') || $$, 4, $$
		|| quote_literal(:'ven') || $$, 'ledger test mint' ) $$,
	'mint_tokens succeeds'
);
select tests.clear_authentication();

select is(
	(select count(*)::int from public.token_events e
		join public.tokens t on t.id = e.token
		where t.currency = :'cur' and e.op = 'mint'),
	4,
	'minting 4 tokens records 4 mint events'
);

select is(
	(select count(*)::int from public.token_events e
		join public.tokens t on t.id = e.token
		where t.currency = :'cur' and e.txn is null),
	0,
	'every event from an RPC carries a transaction id'
);

-- The attribution must point at a transaction that actually exists, not just any
-- uuid — this is what makes the log joinable to the narrative.
select is(
	(select count(*)::int from public.token_events e
		join public.tokens t on t.id = e.token
		left join public.transactions x on x.id = e.txn
		where t.currency = :'cur' and e.txn is not null and x.id is null),
	0,
	'every attributed event references a real transaction'
);

-- ---- 2. A transfer records the previous owner ---------------------------------
-- Give alice two tokens through the venue, then have her gift one to bob.
select tests.authenticate_as(:'admin');
select lives_ok(
	$$ select public.transfer_tokens( $$ || quote_literal(:'cur') || $$, $$
		|| quote_literal(:'ven') || $$, 'venueid', $$
		|| quote_literal(:'alice') || $$, 'scholarid', 2, 'payout', null ) $$,
	'transfer_tokens moves tokens out of the venue reserve'
);

select tests.clear_authentication();
select is(
	(select count(*)::int from public.token_events
		where op = 'move' and prev_venue = :'ven' and scholar = :'alice'),
	2,
	'a transfer records both the new owner and the previous one'
);

-- ---- 3. An out-of-band write is captured, and flagged --------------------------
-- Move a token directly as the OWNER, bypassing every RPC. This is the shape of
-- the thing the ledger exists to catch: an application bug, a careless migration,
-- or a privileged human moving balances by hand.
update public.tokens
set scholar = :'bob'
where scholar = :'alice' and currency = :'cur'
	and id = (select id from public.tokens where scholar = :'alice' and currency = :'cur' order by id limit 1);

select is(
	(select count(*)::int from public.token_events
		where op = 'move' and prev_scholar = :'alice' and scholar = :'bob'),
	1,
	'a direct write that bypasses the RPCs is still captured'
);

select is(
	(select count(*)::int from public.token_events
		where op = 'move' and prev_scholar = :'alice' and scholar = :'bob' and txn is null),
	1,
	'...and is visibly unattributed, which is the corruption alarm'
);

-- ---- 4. The log reconstructs current state exactly -----------------------------
-- The headline property: replaying the log reproduces `tokens` row for row. If
-- this ever fails, a write escaped the trigger.
--
-- No argument, which means clock_timestamp(). Passing now() here would ask for
-- state as of this transaction's START and therefore miss every event the test
-- just created — see the note on tokens_as_of.
select is(
	(select count(*)::int from public.tokens t
		full outer join public.tokens_as_of() a on a.token = t.id
		where t.id is null
			or a.token is null
			or (t.scholar, t.venue, t.currency) is distinct from (a.scholar, a.venue, a.currency)),
	0,
	'tokens_as_of(now()) reproduces the tokens table exactly'
);

-- ---- 5. The per-token chain is continuous --------------------------------------
-- Event N's prev_* must equal event N-1's owner for the same token. A break means
-- a write happened that the trigger did not see, or a partial restore landed.
select is(
	(select count(*)::int from (
		select
			e.prev_scholar, e.prev_venue,
			lag(e.scholar) over w as prior_scholar,
			lag(e.venue) over w as prior_venue,
			lag(e.seq) over w as prior_seq
		from public.token_events e
		window w as (partition by e.token order by e.seq)
	) s
	where prior_seq is not null
		and (s.prev_scholar, s.prev_venue) is distinct from (s.prior_scholar, s.prior_venue)),
	0,
	'each event''s previous owner matches the prior event for that token'
);

select * from finish();
rollback;
