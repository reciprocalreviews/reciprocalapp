-- RLS and append-only tests for public.token_events.
--
-- Authorization model under test:
--   SELECT  nobody through the API. RLS is enabled with NO policies, and the
--           privileges are revoked, so authenticated and anon see nothing.
--           Historical token ownership is not exposed anywhere in the product
--           and would leak reviewing activity that venue anonymity settings
--           exist to protect.
--   INSERT  only the logging trigger (SECURITY DEFINER, runs as the owner).
--   UPDATE  refused, except the one sanctioned erasure path that nulls the
--           personal-data columns and leaves the movement itself intact.
--   DELETE  refused, always, for everyone.
--
-- The append-only guarantee is enforced by a TRIGGER rather than by RLS,
-- deliberately: `postgres` and `service_role` bypass policies, and they are
-- exactly who would be at the keyboard during an incident. These tests therefore
-- run the refusal cases as the OWNER — the strongest caller there is.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();
select tests.create_scholar('te_minter@test.local') as minter \gset
select tests.create_scholar('te_owner@test.local') as owner \gset
select tests.create_currency(array[:'minter']::uuid[]) as cur \gset

-- One token, which the trigger records as a mint.
insert into public.tokens (currency, scholar)
values (:'cur', :'owner')
returning id as tok \gset

select seq as ev_seq
from public.token_events
where token = :'tok'
order by seq desc
limit 1 \gset

-- ---- Policy shape -------------------------------------------------------------
-- No policies at all: RLS is enabled, so an empty policy list denies everything.
select policies_are('public', 'token_events', array[]::text[]);

-- ---- SELECT -------------------------------------------------------------------
-- The denial is at the PRIVILEGE level, not merely the policy level: SELECT is
-- revoked, so these fail closed with 42501 rather than quietly returning no rows.
-- That is deliberate — a revoked privilege cannot be re-opened by someone adding
-- a well-meaning policy later.
select tests.authenticate_as(:'owner');
select throws_ok(
	$$ select 1 from public.token_events where token = $$ || quote_literal(:'tok'),
	'42501',
	null,
	'an authenticated scholar cannot read the token log'
);

select tests.authenticate_as_anon();
select throws_ok(
	$$ select 1 from public.token_events where token = $$ || quote_literal(:'tok'),
	'42501',
	null,
	'anonymous visitors cannot read the token log'
);

-- ---- Capture ------------------------------------------------------------------
select tests.clear_authentication();
select is(
	(select op::text from public.token_events where seq = :'ev_seq'),
	'mint',
	'creating a token records a mint event'
);

-- ---- Append-only, as the OWNER ------------------------------------------------
select throws_ok(
	$$ delete from public.token_events where seq = $$ || :'ev_seq',
	'P0001',
	'public.token_events is append-only; rows are never deleted',
	'not even the owner can delete a token event'
);

select throws_ok(
	$$ update public.token_events set venue = null where seq = $$ || :'ev_seq',
	'P0001',
	'public.token_events is append-only',
	'not even the owner can rewrite a token event'
);

-- ---- The one sanctioned mutation: erasure -------------------------------------
-- Nulls the personal-data columns while leaving the movement — which token, when,
-- under which transaction — fully intact, so balances stay reconstructible after
-- a scholar exercises their right to be forgotten.
select lives_ok(
	$$ set local app.erasure = 'on';
	   update public.token_events set scholar = null, prev_scholar = null, actor = null
	   where seq = $$ || :'ev_seq',
	'erasure may null the subject columns'
);

select is(
	(select token from public.token_events where seq = :'ev_seq'),
	:'tok'::uuid,
	'erasure leaves the movement itself intact'
);

-- Even under the erasure flag, nothing else may change: the flag is a licence to
-- forget a person, not to rewrite history.
select throws_ok(
	$$ set local app.erasure = 'on';
	   update public.token_events set op = 'burn' where seq = $$ || :'ev_seq',
	'P0001',
	'erasure may only null scholar, prev_scholar, and actor',
	'erasure cannot alter the movement itself'
);

select * from finish();
rollback;
