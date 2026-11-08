-- Conservation: a holder's tokens must equal what their transactions say.
--
-- WHY THIS FILE EXISTS
--
-- This invariant ran nowhere but production until 2026-08-30, when it mailed the
-- stewards about a venue whose reserve no longer matched its own history. The
-- reason it had never fired anywhere else is structural: supabase/seed.sql creates
-- tokens with direct INSERTs, so every development and CI database permanently has
-- unattributed_mints > 0, and reconcile_ledger SKIPS check 6 whenever provenance is
-- unexplained. The check was real, the alarm was wired, and no test had ever
-- executed the query.
--
-- So the fixture here is built the way the platform builds one: every token comes
-- into existence through mint_tokens or through an RPC that records what it did.
-- public.conservation_violations takes a currency precisely so a clean economy can
-- be asserted inside a database whose seed is not.
--
-- WHAT IT CAUGHT
--
-- Two paths minted tokens into a venue's reserve and recorded only the transfer
-- that carried them out: _move_tokens's _mint_shortfall branch, reached when a
-- welcome grant is larger than the reserve, and approve_transaction's Branch B.
-- Both are exercised below. Both set app.txn, so the mints were attributed --
-- which is why the ledger looked explained and the balances still did not add up.
-- Attribution says which transaction touched a token; conservation says whether
-- anyone was credited for its creation.
\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(7);

--------------------------------------------------------------------------------
-- Fixtures. One currency, and a venue whose welcome grant is larger than the
-- reserve it will ever hold.
--
-- \gset rather than a temp table of ids: the assertions below run as postgres
-- while the RPCs run as `authenticated`, and a temp table is not readable across
-- that switch. Client-side substitution does not care what role is set.
--------------------------------------------------------------------------------
select tests.clear_authentication();
select tests.create_scholar('cons_minter@test.local') as minter \gset
select tests.create_scholar('cons_admin@test.local') as admin \gset
select tests.create_scholar('cons_newcomer@test.local') as newcomer \gset
select tests.create_scholar('cons_payee@test.local') as payee \gset
select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'admin']::uuid[], 10) as ven \gset
select tests.create_role(:'ven') as rol \gset

--------------------------------------------------------------------------------
-- A reserve created the honest way conserves. The baseline: if this fails,
-- nothing below means anything.
--------------------------------------------------------------------------------
select tests.authenticate_as(:'minter');
select public.mint_tokens(:'cur', 3, :'ven', 'Seed the reserve') as _m \gset
select tests.clear_authentication();

select is_empty(
	format($$ select * from public.conservation_violations(%L::uuid) $$, :'cur'),
	'a currency whose only tokens came from mint_tokens is conserved'
);

--------------------------------------------------------------------------------
-- The welcome grant. 10 owed, 3 held, so 7 are minted into the reserve and all
-- 10 move out. The venue is credited 3 + 7, debited 10, and holds nothing.
--
-- THIS IS THE ASSERTION THAT FAILS ON THE CODE THAT SHIPPED: the 7 were created
-- and never credited, so the venue's expected balance sat at -7 against an actual
-- of 0, permanently, for every venue that ever ran short.
--
-- The admin volunteers the newcomer rather than the newcomer volunteering for
-- themselves, which keeps _notify_new_volunteer's mail out of the fixture.
--------------------------------------------------------------------------------
select tests.authenticate_as(:'admin');
select (public.create_volunteer(:'newcomer', :'rol', true, true, null)
	->> 'welcome_granted')::int as granted \gset
select tests.clear_authentication();

select is(:'granted'::int, 10, 'the newcomer is granted the full welcome amount, most of it newly minted');

select is_empty(
	format($$ select * from public.conservation_violations(%L::uuid) $$, :'cur'),
	'a welcome grant larger than the reserve leaves the economy conserved'
);

select is(
	(select count(*) from public.transactions
		where status = 'approved' and from_scholar is null and from_venue is null
			and to_venue = :'ven' and currency = :'cur' and amount = 7),
	1::bigint,
	'the 7 minted to cover the shortfall are recorded as a mint crediting the reserve'
);

--------------------------------------------------------------------------------
-- approve_transaction's Branch B: a proposal carrying placeholders against a
-- reserve that is now empty. Separate code path, same requirement.
--------------------------------------------------------------------------------
select gen_random_uuid() as prop \gset

insert into public.transactions (
	id, creator, from_scholar, from_venue, to_scholar, to_venue,
	tokens, currency, purpose, status
) values (
	:'prop', :'admin', null, :'ven', :'payee', null,
	array_fill('00000000-0000-0000-0000-000000000000'::uuid, array[3]),
	:'cur', 'Compensation the reserve cannot cover', 'proposed'
);

select tests.authenticate_as(:'minter');
select lives_ok(
	format($$ select public.approve_transaction(%L::uuid) $$, :'prop'),
	'a minter can approve a payout the reserve cannot cover'
);
select tests.clear_authentication();

select is_empty(
	format($$ select * from public.conservation_violations(%L::uuid) $$, :'cur'),
	'approving a payout that mints its own shortfall leaves the economy conserved'
);

--------------------------------------------------------------------------------
-- Negative control. Every assertion above is is_empty, and an is_empty that
-- cannot go red is decoration -- the point of this file is that a check nothing
-- exercises proves nothing. One token with no transaction behind it is exactly
-- what the production incident consisted of, so it must be reported.
--------------------------------------------------------------------------------
insert into public.tokens (currency, venue, scholar) values (:'cur', :'ven', null);

select results_eq(
	format($$ select kind, holder, expected, actual from public.conservation_violations(%L::uuid) $$, :'cur'),
	format($$ values ('venue'::text, %L::uuid, 0::bigint, 1::bigint) $$, :'ven'),
	'a token created with no transaction crediting anyone is reported as drift'
);

select * from finish ();

rollback;
