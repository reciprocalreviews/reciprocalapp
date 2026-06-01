-- RLS tests for public.tokens.
--
-- Authorization model under test:
--   SELECT  authenticated scholars only (using = true) — anon cannot read.
--   INSERT  currency minters only.
--   UPDATE  the owning scholar, the owning venue's admins, or a priority-0 role
--           holder at the owning venue. Currency minters mint tokens (INSERT)
--           but must NOT be able to move ownership of existing tokens.
--   DELETE  blocked for everyone (using = false).

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(13);

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();
select tests.create_scholar('tok_minter@test.local') as minter \gset
select tests.create_scholar('tok_owner@test.local') as owner \gset
select tests.create_scholar('tok_vadmin@test.local') as vadmin \gset
select tests.create_scholar('tok_pzero@test.local') as pzero \gset
select tests.create_scholar('tok_outsider@test.local') as outsider \gset

-- A currency minted by :minter, and a venue administered by :vadmin (distinct
-- from the minter so the no_minter_admins trigger does not fire).
select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'vadmin']::uuid[]) as ven \gset

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
		'tokens are visible to authenticated scholars',
		'only minters can create tokens',
		'owners, admins, and priority-0 roles can update tokens',
		'tokens cannot be deleted'
	]
);

-- ---- SELECT -------------------------------------------------------------------
-- Any authenticated scholar may read tokens (using = true).
select tests.authenticate_as(:'outsider');
select isnt_empty(
	$$ select 1 from public.tokens where id = $$ || quote_literal(:'tok_scholar'),
	'an authenticated scholar can read tokens'
);

-- Anonymous visitors cannot read any token.
select tests.authenticate_as_anon();
select is_empty(
	$$ select 1 from public.tokens where id = $$ || quote_literal(:'tok_scholar'),
	'anonymous visitors cannot read tokens'
);

-- ---- INSERT -------------------------------------------------------------------
-- A currency minter may mint a token in their currency.
select tests.authenticate_as(:'minter');
select lives_ok(
	$$ insert into public.tokens (currency, scholar)
	   values ( $$ || quote_literal(:'cur') || $$, $$ || quote_literal(:'owner') || $$ ) $$,
	'a currency minter can mint a token'
);

-- A non-minter cannot mint a token (WITH CHECK violation).
select tests.authenticate_as(:'outsider');
select throws_ok(
	$$ insert into public.tokens (currency, scholar)
	   values ( $$ || quote_literal(:'cur') || $$, $$ || quote_literal(:'outsider') || $$ ) $$,
	'42501',
	null,
	'a non-minter cannot mint a token'
);

-- ---- UPDATE -------------------------------------------------------------------
-- The owning scholar may transfer their own token to the venue.
select tests.authenticate_as(:'owner');
select lives_ok(
	$$ update public.tokens set scholar = null, venue = $$ || quote_literal(:'ven')
	   || $$ where id = $$ || quote_literal(:'tok_scholar'),
	'the owning scholar can transfer their token'
);
select tests.clear_authentication();
select is(
	(select venue from public.tokens where id = :'tok_scholar'),
	:'ven'::uuid,
	'the scholar-owned token now belongs to the venue'
);

-- A venue admin may move a venue-owned token to a scholar.
select tests.authenticate_as(:'vadmin');
select lives_ok(
	$$ update public.tokens set venue = null, scholar = $$ || quote_literal(:'owner')
	   || $$ where id = $$ || quote_literal(:'tok_venue'),
	'a venue admin can move a venue-owned token'
);
-- Put it back so the priority-0 case below has a venue-owned token to act on.
select tests.clear_authentication();
update public.tokens set scholar = null, venue = :'ven' where id = :'tok_venue';

-- A priority-0 role holder at the owning venue may move a venue-owned token.
select tests.authenticate_as(:'pzero');
select lives_ok(
	$$ update public.tokens set venue = null, scholar = $$ || quote_literal(:'pzero')
	   || $$ where id = $$ || quote_literal(:'tok_venue'),
	'a priority-0 role holder can move a venue-owned token'
);

-- Adversarial: a currency minter who is neither owner, admin, nor a priority-0
-- role holder must NOT be able to change ownership. The using clause filters the
-- row out, so the update affects 0 rows rather than throwing — verify it stuck.
select tests.clear_authentication();
update public.tokens set scholar = null, venue = :'ven' where id = :'tok_venue';
select tests.authenticate_as(:'minter');
update public.tokens set venue = null, scholar = :'minter' where id = :'tok_venue';
select tests.clear_authentication();
select is(
	(select venue from public.tokens where id = :'tok_venue'),
	:'ven'::uuid,
	'a minter cannot move ownership of an existing token (no-op)'
);

-- Adversarial: an unrelated scholar cannot transfer a scholar-owned token.
select tests.clear_authentication();
update public.tokens set venue = null, scholar = :'owner' where id = :'tok_scholar';
select tests.authenticate_as(:'outsider');
update public.tokens set scholar = :'outsider' where id = :'tok_scholar';
select tests.clear_authentication();
select is(
	(select scholar from public.tokens where id = :'tok_scholar'),
	:'owner'::uuid,
	'an unrelated scholar cannot transfer a token they do not own (no-op)'
);

-- ---- DELETE -------------------------------------------------------------------
-- Nobody may delete a token (using = false → 0 rows, no error).
-- Even the owning scholar is blocked.
select tests.authenticate_as(:'owner');
delete from public.tokens where id = :'tok_scholar';
select tests.clear_authentication();
select is(
	(select count(*)::int from public.tokens where id = :'tok_scholar'),
	1,
	'the owning scholar cannot delete a token'
);

-- A currency minter likewise cannot delete a token.
select tests.authenticate_as(:'minter');
delete from public.tokens where id = :'tok_venue';
select tests.clear_authentication();
select is(
	(select count(*)::int from public.tokens where id = :'tok_venue'),
	1,
	'a currency minter cannot delete a token'
);

select * from finish();
rollback;
