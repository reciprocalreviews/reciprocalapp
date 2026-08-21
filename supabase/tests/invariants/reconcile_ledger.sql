-- Tests for public.reconcile_ledger().
--
-- A monitoring check is only worth having if it fires. Each test below breaks one
-- invariant deliberately and asserts that the corresponding count moves — because
-- a checker that returns `ok` no matter what is worse than none, in that it
-- actively reassures.
--
-- Every case runs as the OWNER, since that is the only role that can produce this
-- corruption at all: the write boundary from 20260802010000 prevents clients from
-- touching tokens directly, so the failures being simulated are application bugs,
-- careless migrations, and hand-repairs gone wrong.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

select tests.clear_authentication();
select tests.create_scholar('rec_minter@test.local') as minter \gset
select tests.create_scholar('rec_admin@test.local') as admin \gset
select tests.create_scholar('rec_alice@test.local') as alice \gset
select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as ven \gset

-- ---- Healthy baseline ----------------------------------------------------------
-- The seed inserts tokens directly, so this database always carries unattributed
-- mints. That is why they are advisory rather than part of `ok` — assert the
-- distinction holds, since it is what keeps the check readable.
select is(
	(public.reconcile_ledger() -> 'ok')::text,
	'true',
	'a healthy database reports ok'
);

select cmp_ok(
	((public.reconcile_ledger() -> 'advisory' ->> 'unattributed_mints')::int),
	'>', 0,
	'seeded databases report unattributed mints as advisory, not failure'
);

-- ---- 1. Unattributed movement --------------------------------------------------
-- The headline alarm: value moving with no transaction to explain it. Simulated
-- exactly as a bug or a hand-repair would do it — a direct UPDATE as the owner.
select tests.authenticate_as(:'minter');
select public.mint_tokens(:'cur', 3, :'ven', 'reconcile test') as _m \gset
select tests.clear_authentication();

update public.tokens
set venue = null, scholar = :'alice'
where id = (select id from public.tokens where venue = :'ven' and currency = :'cur' limit 1);

select is(
	((public.reconcile_ledger() -> 'invariants' ->> 'unattributed_moves')::int),
	1,
	'a direct token move is reported as unattributed'
);

select is(
	(public.reconcile_ledger() -> 'ok')::text,
	'false',
	'...and that alone makes the run fail'
);

-- ---- 2. Conservation is skipped, not guessed at --------------------------------
-- With provenance already broken, a conservation number would be noise dressed as
-- signal. Assert it declines to report rather than emitting false violations.
select alike(
	(public.reconcile_ledger() -> 'invariants' ->> 'conservation_violations'),
	'skipped%',
	'conservation is skipped while provenance is unexplained'
);

-- ---- 3. Placeholders in approved history ---------------------------------------
-- An approved transaction still holding null-UUIDs records an amount for a
-- movement that never happened.
insert into public.transactions (creator, to_venue, tokens, currency, purpose, status)
values (
	:'minter', :'ven',
	array['00000000-0000-0000-0000-000000000000'::uuid],
	:'cur', 'placeholder left behind', 'approved'
);

select is(
	((public.reconcile_ledger() -> 'invariants' ->> 'placeholders_in_approved')::int),
	1,
	'an approved transaction holding placeholders is reported'
);

-- ---- 4. Dangling token references ----------------------------------------------
-- An approved transaction citing a token that does not exist.
insert into public.transactions (creator, to_venue, tokens, currency, purpose, status)
values (
	:'minter', :'ven',
	array[gen_random_uuid()],
	:'cur', 'cites a token that never existed', 'approved'
);

select is(
	((public.reconcile_ledger() -> 'invariants' ->> 'dangling_token_refs')::int),
	1,
	'an approved transaction citing a missing token is reported'
);

-- ---- 5. Chain continuity --------------------------------------------------------
-- Tampering the log cannot be simulated through the erasure hatch — that guard
-- only permits NULLING the subject columns, and it refuses this outright, which is
-- itself the behaviour we want. So simulate the realistic case instead: a stray
-- event whose "previous owner" does not follow from the one before it.
--
-- That is exactly the shape a partial restore leaves behind. A restore loads data
-- with session_replication_role = replica, so the logging trigger never fires and
-- rows arrive that no live write produced — which a plain state comparison cannot
-- detect, because the end state can still look entirely correct.
insert into public.token_events (token, op, currency, scholar, venue, prev_scholar, prev_venue)
select
	t.id, 'move', t.currency, :'alice'::uuid, null,
	:'admin'::uuid, null   -- claims admin held it; the prior event says otherwise
from public.tokens t
where t.currency = :'cur'
limit 1;

select cmp_ok(
	((public.reconcile_ledger() -> 'invariants' ->> 'chain_breaks')::int),
	'>=', 1,
	'an event whose previous owner does not follow is reported as a chain break'
);

-- ---- 6. Every run is recorded ---------------------------------------------------
-- The table is what makes a trend visible; a function nobody stores tells you only
-- about this instant.
select cmp_ok(
	(select count(*)::int from public.reconciliations),
	'>=', 8,
	'each run appends a row to public.reconciliations'
);

select * from finish();
rollback;
