-- RLS tests for public.transactions.
--
-- Authorization model under test:
--   SELECT  creator, from/to scholar, currency minters, from/to venue admins.
--   INSERT  anyone may propose; an approved row must be a legitimate transfer
--           (giver spending own balance, from-venue admin paying out, or a mint
--           with no source) AND must not enrich the approver (no-self-dealing).
--           The column grant omits `id` and `created_at`, so a caller may propose
--           a transaction but may not choose its identity or backdate it.
--   UPDATE  givers, currency minters, from-venue admins — but only status/decline
--           (and tokens); identity columns are revoked (immutable record).
--   DELETE  nobody. This policy's USING clause used to match the currency's
--           minters, so its name said one thing and its body did the opposite: a
--           minter could erase approved transfer history while the tokens those
--           rows described stayed put, leaving tokens with no account of how they
--           got where they are.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(20);

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();
select tests.create_scholar('txn_minter@test.local') as minter \gset
select tests.create_scholar('txn_recipient@test.local') as recipient \gset
select tests.create_scholar('txn_vadmin@test.local') as vadmin \gset
select tests.create_scholar('txn_outsider@test.local') as outsider \gset
select tests.create_scholar('txn_nobody@test.local') as nobody \gset
select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'vadmin']::uuid[]) as ven \gset

-- A mint (no source) → recipient.
insert into public.transactions (creator, to_scholar, tokens, currency, purpose, status)
values (:'outsider', :'recipient', array['00000000-0000-0000-0000-000000000000'::uuid], :'cur', 'mint', 'proposed')
returning id as txn_mint \gset
-- A mint → minter (approving this would enrich the minter).
insert into public.transactions (creator, to_scholar, tokens, currency, purpose, status)
values (:'outsider', :'minter', array['00000000-0000-0000-0000-000000000000'::uuid], :'cur', 'mint self', 'proposed')
returning id as txn_mint_self \gset
-- A venue payout → recipient.
insert into public.transactions (creator, from_venue, to_scholar, tokens, currency, purpose, status)
values (:'outsider', :'ven', :'recipient', array['00000000-0000-0000-0000-000000000000'::uuid], :'cur', 'payout', 'proposed')
returning id as txn_venue \gset
-- A venue payout → the approving admin (self-dealing).
insert into public.transactions (creator, from_venue, to_scholar, tokens, currency, purpose, status)
values (:'outsider', :'ven', :'vadmin', array['00000000-0000-0000-0000-000000000000'::uuid], :'cur', 'payout self', 'proposed')
returning id as txn_venue_self \gset
-- A mint used for the delete tests.
insert into public.transactions (creator, to_scholar, tokens, currency, purpose, status)
values (:'outsider', :'recipient', array['00000000-0000-0000-0000-000000000000'::uuid], :'cur', 'deletable', 'proposed')
returning id as txn_del \gset

-- ---- Policy shape -------------------------------------------------------------
select policies_are(
	'public', 'transactions',
	array[
		'transactions are only visible to minters and those involved',
		'only owners can transfer their tokens if approved',
		'only the giver and minters can update transactions',
		'transactions cannot be deleted'
	]
);

-- ---- SELECT -------------------------------------------------------------------
select tests.authenticate_as(:'minter');
select isnt_empty(
	$$ select 1 from public.transactions where id = $$ || quote_literal(:'txn_mint'),
	'currency minter can see a transaction in their currency'
);

select tests.authenticate_as(:'recipient');
select isnt_empty(
	$$ select 1 from public.transactions where id = $$ || quote_literal(:'txn_mint'),
	'recipient can see a transaction sent to them'
);

select tests.authenticate_as(:'vadmin');
select isnt_empty(
	$$ select 1 from public.transactions where id = $$ || quote_literal(:'txn_venue'),
	'from-venue admin can see the venue payout'
);

select tests.authenticate_as(:'nobody');
select is_empty(
	$$ select 1 from public.transactions where id = $$ || quote_literal(:'txn_mint'),
	'an unrelated scholar cannot see the transaction'
);

select tests.authenticate_as_anon();
select is_empty(
	$$ select 1 from public.transactions where id = $$ || quote_literal(:'txn_mint'),
	'anonymous visitors cannot see transactions'
);

-- ---- UPDATE (approval) --------------------------------------------------------
-- A minter may approve a mint to a third party.
select tests.authenticate_as(:'minter');
select lives_ok(
	$$ update public.transactions set status = 'approved' where id = $$ || quote_literal(:'txn_mint'),
	'minter can approve a mint to a third party'
);
select tests.clear_authentication();
select is(
	(select status::text from public.transactions where id = :'txn_mint'),
	'approved',
	'the mint is now approved'
);

-- A from-venue admin may approve a venue payout to a third party.
select tests.authenticate_as(:'vadmin');
select lives_ok(
	$$ update public.transactions set status = 'approved' where id = $$ || quote_literal(:'txn_venue'),
	'from-venue admin can approve a venue payout to a third party'
);

-- A minter may NOT approve a mint that pays the minter (self-enrichment).
select tests.authenticate_as(:'minter');
select throws_ok(
	$$ update public.transactions set status = 'approved' where id = $$ || quote_literal(:'txn_mint_self'),
	'42501',
	null,
	'minter cannot approve a mint that enriches themselves'
);

-- A from-venue admin may NOT approve a payout to themselves (self-enrichment).
select tests.authenticate_as(:'vadmin');
select throws_ok(
	$$ update public.transactions set status = 'approved' where id = $$ || quote_literal(:'txn_venue_self'),
	'42501',
	null,
	'venue admin cannot approve a payout that enriches themselves'
);

-- An unrelated scholar's UPDATE is filtered by the using clause (0 rows, no error).
select tests.authenticate_as(:'outsider');
update public.transactions set status = 'approved' where id = :'txn_del';
select tests.clear_authentication();
select is(
	(select status::text from public.transactions where id = :'txn_del'),
	'proposed',
	'an unrelated scholar cannot approve a transaction (no-op)'
);

-- ---- UPDATE (immutability) ----------------------------------------------------
-- Identity columns are revoked from authenticated, even for a legitimate updater.
select tests.authenticate_as(:'minter');
select throws_ok(
	$$ update public.transactions set purpose = 'tampered' where id = $$ || quote_literal(:'txn_mint'),
	'42501',
	null,
	'a transaction is immutable: even a minter cannot edit identity columns'
);

-- ---- INSERT -------------------------------------------------------------------
select tests.authenticate_as(:'outsider');
select lives_ok(
	$$ insert into public.transactions (creator, to_scholar, tokens, currency, purpose, status)
	   values ( $$ || quote_literal(:'outsider') || $$, $$ || quote_literal(:'recipient') || $$,
	            array['00000000-0000-0000-0000-000000000000'::uuid], $$ || quote_literal(:'cur') || $$,
	            'proposal', 'proposed') $$,
	'anyone can propose a transaction'
);

-- A scholar cannot insert an already-approved mint that pays themselves.
select tests.authenticate_as(:'recipient');
select throws_ok(
	$$ insert into public.transactions (creator, to_scholar, tokens, currency, purpose, status)
	   values ( $$ || quote_literal(:'recipient') || $$, $$ || quote_literal(:'recipient') || $$,
	            array['00000000-0000-0000-0000-000000000000'::uuid], $$ || quote_literal(:'cur') || $$,
	            'self mint', 'approved') $$,
	'42501',
	null,
	'a scholar cannot insert an approved mint that enriches themselves'
);

-- ---- INSERT (identity columns) ------------------------------------------------
-- The column grant omits `id`, so a caller cannot choose a transaction's identity
-- (which would let them collide with, or squat on, an id another write expects).
select tests.authenticate_as(:'outsider');
select throws_ok(
	$$ insert into public.transactions (id, creator, to_scholar, tokens, currency, purpose, status)
	   values ( gen_random_uuid(), $$ || quote_literal(:'outsider') || $$, $$
	            || quote_literal(:'recipient') || $$,
	            array['00000000-0000-0000-0000-000000000000'::uuid], $$ || quote_literal(:'cur') || $$,
	            'chosen id', 'proposed') $$,
	'42501',
	null,
	'a caller cannot choose a transaction id'
);

-- ...and omits `created_at`, so history cannot be backdated.
select throws_ok(
	$$ insert into public.transactions (created_at, creator, to_scholar, tokens, currency, purpose, status)
	   values ( '2000-01-01T00:00:00Z', $$ || quote_literal(:'outsider') || $$, $$
	            || quote_literal(:'recipient') || $$,
	            array['00000000-0000-0000-0000-000000000000'::uuid], $$ || quote_literal(:'cur') || $$,
	            'backdated', 'proposed') $$,
	'42501',
	null,
	'a caller cannot backdate a transaction'
);

-- ---- DELETE -------------------------------------------------------------------
-- Nobody deletes history. The privilege is revoked, not merely denied by policy,
-- so an attempt raises rather than quietly affecting 0 rows.
select tests.authenticate_as(:'outsider');
select throws_ok(
	$$ delete from public.transactions where id = $$ || quote_literal(:'txn_del'),
	'42501',
	null,
	'a non-minter cannot delete a transaction'
);

-- A currency minter is likewise blocked — this is the case that used to succeed.
select tests.authenticate_as(:'minter');
select throws_ok(
	$$ delete from public.transactions where id = $$ || quote_literal(:'txn_del'),
	'42501',
	null,
	'a currency minter cannot delete a transaction'
);

select tests.clear_authentication();
select is(
	(select count(*)::int from public.transactions where id = :'txn_del'),
	1,
	'the transaction survives every deletion attempt'
);

select * from finish();
rollback;
