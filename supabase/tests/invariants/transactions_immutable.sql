-- Tests for the transactions immutability trigger.
--
-- Two rules that the column grants cannot express, because both depend on what
-- the row already is rather than on who is asking:
--
--   1. A decided transaction cannot be changed again.
--   2. The token count — which IS the amount, since there is no amount column —
--      may be filled in but never resized.
--
-- The refusals are exercised as the OWNER, because that is the strongest caller
-- there is: a trigger that only stopped `authenticated` would not stop the RPCs,
-- a migration, or a hand-repair, which are exactly the ways this corruption
-- would realistically arrive.
--
-- Just as important, the legitimate paths must still work, so approval and
-- decline are both driven end to end below. A rule that also blocks correct
-- behaviour is worse than no rule.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(10);

select tests.clear_authentication();
select tests.create_scholar('imm_minter@test.local') as minter \gset
select tests.create_scholar('imm_admin@test.local') as admin \gset
select tests.create_scholar('imm_alice@test.local') as alice \gset
select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as ven \gset

-- ---- The legitimate paths still work ------------------------------------------
select tests.authenticate_as(:'minter');
select lives_ok(
	$$ select public.mint_tokens( $$ || quote_literal(:'cur') || $$ , 4, $$
		|| quote_literal(:'ven') || $$ , 'immutability fixture' ) $$,
	'minting still works with the trigger in place'
);
select tests.clear_authentication();

-- A proposed payout the venue admin can approve.
insert into public.transactions (creator, from_venue, to_scholar, tokens, currency, purpose, status)
values (
	:'admin', :'ven', :'alice',
	array_fill('00000000-0000-0000-0000-000000000000'::uuid, array[2]),
	:'cur', 'payout to approve', 'proposed'
)
returning id as txn_approve \gset

-- Approved by the MINTER, not the admin: a proposed transaction carries
-- placeholder UUIDs, and approve_transaction mints that shortfall into the venue
-- reserve just in time — which only a currency minter may do. The minter is not
-- the recipient, so the anti-self-dealing rule is satisfied.
select tests.authenticate_as(:'minter');
select lives_ok(
	$$ select public.approve_transaction( $$ || quote_literal(:'txn_approve') || $$ ) $$,
	'a proposed transaction can still be approved'
);
select tests.clear_authentication();

select is(
	(select status::text from public.transactions where id = :'txn_approve'),
	'approved',
	'...and the approval stuck'
);

-- Approval must have replaced the placeholders with real ids, same count.
select is(
	(select cardinality(tokens) from public.transactions where id = :'txn_approve'),
	2,
	'approval fills the placeholders without changing the count'
);

-- ---- 1. Terminality ------------------------------------------------------------
-- The race this closes: tokens have already moved and been recorded, so flipping
-- the transaction to declined afterwards would leave the ledger and the narrative
-- contradicting each other.
select throws_ok(
	$$ update public.transactions set status = 'declined', decliner = $$ || quote_literal(:'minter')
		|| $$ , decline_reason = 'too late' where id = $$ || quote_literal(:'txn_approve'),
	'RR005',
	null,
	'an approved transaction cannot then be declined'
);

select throws_ok(
	$$ update public.transactions set status = 'proposed' where id = $$ || quote_literal(:'txn_approve'),
	'RR005',
	null,
	'an approved transaction cannot be reopened'
);

select is(
	(select status::text from public.transactions where id = :'txn_approve'),
	'approved',
	'...and it is still approved after both attempts'
);

-- Declining is likewise terminal.
insert into public.transactions (creator, from_venue, to_scholar, tokens, currency, purpose, status)
values (
	:'admin', :'ven', :'alice',
	array_fill('00000000-0000-0000-0000-000000000000'::uuid, array[1]),
	:'cur', 'payout to decline', 'proposed'
)
returning id as txn_decline \gset

update public.transactions
set status = 'declined', decliner = :'admin', decline_reason = 'not this time'
where id = :'txn_decline';

select throws_ok(
	$$ update public.transactions set status = 'approved' where id = $$ || quote_literal(:'txn_decline'),
	'RR005',
	null,
	'a declined transaction cannot then be approved'
);

-- ---- 2. Amount preservation ----------------------------------------------------
-- cardinality(tokens) is the only record of how much moved, so resizing it
-- rewrites the amount of a transfer after the fact.
insert into public.transactions (creator, from_venue, to_scholar, tokens, currency, purpose, status)
values (
	:'admin', :'ven', :'alice',
	array_fill('00000000-0000-0000-0000-000000000000'::uuid, array[2]),
	:'cur', 'amount tampering', 'proposed'
)
returning id as txn_amount \gset

select throws_ok(
	$$ update public.transactions
	   set tokens = array_fill('00000000-0000-0000-0000-000000000000'::uuid, array[9])
	   where id = $$ || quote_literal(:'txn_amount'),
	'RR005',
	null,
	'a proposed transaction cannot be resized'
);

-- Replacing placeholders with the same number of real ids is the whole point of
-- approval, and must still be allowed.
select lives_ok(
	$$ update public.transactions
	   set tokens = array[gen_random_uuid(), gen_random_uuid()]
	   where id = $$ || quote_literal(:'txn_amount'),
	'...but its placeholders may still be filled in at the same count'
);

select * from finish();
rollback;
