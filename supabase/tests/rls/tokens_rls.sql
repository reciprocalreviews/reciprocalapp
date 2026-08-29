-- RLS tests for public.tokens.
--
-- Authorization model under test:
--   SELECT  a scholar's own tokens, plus any venue's reserve. Anon reads
--           nothing. Balances are private (#109): nobody reads anybody else's
--           token rows through this table, whatever their role — the audience
--           rule lives in scholar_balances instead, so that a policy evaluated
--           once per token row stays two column comparisons.
--   INSERT  nobody, directly. Tokens are minted only by mint_tokens.
--   UPDATE  nobody, directly. Ownership moves only through transfer_tokens,
--           approve_transaction, complete_assignment, mark_submission_done,
--           create_submission, and bulk_import_submissions.
--   DELETE  nobody.
--
-- The write privileges are REVOKED from authenticated/anon, not merely denied by
-- policy, so a direct attempt raises 42501 rather than quietly affecting 0 rows.
-- The deny policies exist alongside the revoke to document the intent and to let
-- policies_are() assert it.
--
-- This replaces a model in which the owning scholar could UPDATE their own token
-- rows with `with check (true)`. That pinned nothing about the resulting row: a
-- scholar could reassign a token to anyone with no transactions row written, and
-- could rewrite the token's `currency` to counterfeit value in a currency they
-- were never granted (balances are count(*) of token rows). Both are asserted
-- blocked below.
--
-- The happy paths for the SECURITY DEFINER RPCs live in ../rpc/atomic_crud_rpc.sql;
-- one mint is repeated here as a direct guard that revoking the grants did not
-- also break the definer path.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(21);

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();
select tests.create_scholar('tok_minter@test.local') as minter \gset
select tests.create_scholar('tok_owner@test.local') as owner \gset
select tests.create_scholar('tok_vadmin@test.local') as vadmin \gset
select tests.create_scholar('tok_pzero@test.local') as pzero \gset
select tests.create_scholar('tok_outsider@test.local') as outsider \gset

-- A currency minted by :minter, and a venue administered by :vadmin (distinct
-- from the minter, so nothing here turns on the admin/minter overlap).
select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'vadmin']::uuid[]) as ven \gset

-- A second currency :minter does NOT mint, used for the counterfeit probe.
select tests.create_currency(array[:'outsider']::uuid[]) as other_cur \gset

-- A priority-0 role at the venue, with :pzero an accepted volunteer in it.
select tests.create_role(:'ven', 0) as role \gset
select tests.create_volunteer(:'pzero', :'role') as vol \gset

-- A token currently owned by :owner (a scholar-owned token).
insert into public.tokens (currency, scholar)
values (:'cur', :'owner')
returning id as tok_scholar \gset

-- A token currently owned by the venue (a venue-owned token).
insert into public.tokens (currency, venue)
values (:'cur', :'ven')
returning id as tok_venue \gset

-- ---- Policy shape -------------------------------------------------------------
select policies_are(
	'public', 'tokens',
	array[
		'tokens are visible to their holder, and venue reserves to any scholar',
		'tokens are only created by definer rpcs',
		'tokens are only updated by definer rpcs',
		'tokens cannot be deleted'
	]
);

-- ---- SELECT -------------------------------------------------------------------
-- Balances are private (#109). This section used to assert the opposite -- that
-- :outsider, a scholar with no relationship to this currency, venue or token,
-- could read it -- because the policy was `using (true)`. That assertion was an
-- accurate description of a leak: any signed-in scholar could list this table and
-- reconstruct who held how much of what across the whole platform.

-- A scholar reads their own tokens.
select tests.authenticate_as(:'owner');
select isnt_empty(
	$$ select 1 from public.tokens where id = $$ || quote_literal(:'tok_scholar'),
	'a scholar can read their own tokens'
);

-- And nobody else's. Not an unrelated scholar...
select tests.authenticate_as(:'outsider');
select is_empty(
	$$ select 1 from public.tokens where id = $$ || quote_literal(:'tok_scholar'),
	'an unrelated scholar cannot read another scholar''s tokens'
);

-- ...and not the venue admin or the priority-0 editor either. Both ARE in the
-- balance audience, but they reach it through scholar_balances, which asks the
-- audience question once per call. The table itself tells them nothing, so a
-- widened audience can never turn into a per-row cost here by accident.
select tests.authenticate_as(:'vadmin');
select is_empty(
	$$ select 1 from public.tokens where id = $$ || quote_literal(:'tok_scholar'),
	'a venue admin cannot read a scholar''s tokens through the table'
);

select tests.authenticate_as(:'pzero');
select is_empty(
	$$ select 1 from public.tokens where id = $$ || quote_literal(:'tok_scholar'),
	'a priority-0 editor cannot read a scholar''s tokens through the table'
);

-- A venue's reserve is institutional rather than personal, and stays readable by
-- any signed-in scholar: someone deciding whether to volunteer is entitled to
-- know whether the venue can pay.
select tests.authenticate_as(:'outsider');
select isnt_empty(
	$$ select 1 from public.tokens where id = $$ || quote_literal(:'tok_venue'),
	'any signed-in scholar can read a venue reserve token'
);

-- Anonymous visitors read nothing at all, reserves included.
select tests.authenticate_as_anon();
select is_empty(
	$$ select 1 from public.tokens where id = $$ || quote_literal(:'tok_scholar'),
	'anonymous visitors cannot read tokens'
);
select is_empty(
	$$ select 1 from public.tokens where id = $$ || quote_literal(:'tok_venue'),
	'anonymous visitors cannot read venue reserves either'
);

-- ---- INSERT -------------------------------------------------------------------
-- Even a currency minter cannot insert a token directly; minting is mint_tokens'
-- job, which also records the matching approved transaction in the same
-- statement. A bare INSERT would create value with no record of its creation.
select tests.authenticate_as(:'minter');
select throws_ok(
	$$ insert into public.tokens (currency, scholar)
	   values ( $$ || quote_literal(:'cur') || $$, $$ || quote_literal(:'owner') || $$ ) $$,
	'42501',
	null,
	'a currency minter cannot insert a token directly'
);

select tests.authenticate_as(:'outsider');
select throws_ok(
	$$ insert into public.tokens (currency, scholar)
	   values ( $$ || quote_literal(:'cur') || $$, $$ || quote_literal(:'outsider') || $$ ) $$,
	'42501',
	null,
	'a non-minter cannot insert a token directly'
);

-- ---- UPDATE -------------------------------------------------------------------
-- The owning scholar cannot move their own token. This is the hole this model
-- closes: it was previously allowed, and wrote no transactions row.
select tests.authenticate_as(:'owner');
select throws_ok(
	$$ update public.tokens set scholar = null, venue = $$ || quote_literal(:'ven')
	   || $$ where id = $$ || quote_literal(:'tok_scholar'),
	'42501',
	null,
	'the owning scholar cannot transfer their token directly'
);

-- Nor can the owning scholar relabel the token into another currency, which
-- would counterfeit value: balances are count(*) of token rows per currency.
select throws_ok(
	$$ update public.tokens set currency = $$ || quote_literal(:'other_cur')
	   || $$ where id = $$ || quote_literal(:'tok_scholar'),
	'42501',
	null,
	'the owning scholar cannot relabel a token into another currency'
);

-- A venue admin cannot move a venue-owned token directly.
select tests.authenticate_as(:'vadmin');
select throws_ok(
	$$ update public.tokens set venue = null, scholar = $$ || quote_literal(:'owner')
	   || $$ where id = $$ || quote_literal(:'tok_venue'),
	'42501',
	null,
	'a venue admin cannot move a venue-owned token directly'
);

-- Nor can a priority-0 role holder at the owning venue.
select tests.authenticate_as(:'pzero');
select throws_ok(
	$$ update public.tokens set venue = null, scholar = $$ || quote_literal(:'pzero')
	   || $$ where id = $$ || quote_literal(:'tok_venue'),
	'42501',
	null,
	'a priority-0 role holder cannot move a venue-owned token directly'
);

-- Nothing above moved anything.
select tests.clear_authentication();
select is(
	(select scholar from public.tokens where id = :'tok_scholar'),
	:'owner'::uuid,
	'the scholar-owned token still belongs to its owner'
);
select is(
	(select venue from public.tokens where id = :'tok_venue'),
	:'ven'::uuid,
	'the venue-owned token still belongs to the venue'
);

-- ---- DELETE -------------------------------------------------------------------
select tests.authenticate_as(:'owner');
select throws_ok(
	$$ delete from public.tokens where id = $$ || quote_literal(:'tok_scholar'),
	'42501',
	null,
	'the owning scholar cannot delete a token'
);

select tests.authenticate_as(:'minter');
select throws_ok(
	$$ delete from public.tokens where id = $$ || quote_literal(:'tok_venue'),
	'42501',
	null,
	'a currency minter cannot delete a token'
);

select tests.clear_authentication();
select is(
	(select count(*)::int from public.tokens where id in (:'tok_scholar', :'tok_venue')),
	2,
	'both tokens survive every deletion attempt'
);

-- ---- The definer path still works ---------------------------------------------
-- Revoking the grants must not disturb the SECURITY DEFINER RPCs, which are
-- owned by postgres and therefore unaffected by them. (Full RPC coverage lives
-- in ../rpc/atomic_crud_rpc.sql.)
select tests.authenticate_as(:'minter');
select lives_ok(
	$$ select public.mint_tokens( $$ || quote_literal(:'cur') || $$, 3, $$
		|| quote_literal(:'ven') || $$, 'mint still works' ) $$,
	'mint_tokens still mints after the direct write privileges are revoked'
);
select tests.clear_authentication();
select is(
	(select count(*)::int from public.tokens where venue = :'ven' and currency = :'cur'),
	4,
	'the venue holds its original token plus the three newly minted'
);

select * from finish();
rollback;
