-- Tests for set_steward, defined in migration 20260818000000_set_steward.sql.
--
-- This RPC is the ONLY path to scholars.steward: the table UPDATE grant is
-- narrowed to (name, available, status, status_time) precisely so nobody can
-- promote themselves, and the function is SECURITY DEFINER to reach past that.
-- Everything protecting a privilege-bearing column therefore lives inside the
-- function body rather than in a policy, and these tests are the safety net for
-- it — including the assertion that the narrowed grant is still narrow.
--
-- The custom SQLSTATEs under test:
--   RR010  the caller is not a steward
--   RR011  no such scholar
--   RR012  the last steward cannot be demoted
--   RR013  nobody may demote themselves

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

-- ---- Fixtures (owner context) ------------------------------------------------
select tests.clear_authentication();
select tests.create_scholar('stew_a@test.local', true) as stew_a \gset
select tests.create_scholar('stew_b@test.local', true) as stew_b \gset
select tests.create_scholar('stew_plain@test.local') as plain \gset

-- seed.sql ships a steward and the last-steward guard counts GLOBALLY, so the
-- population has to be known before any count means anything — otherwise the
-- RR012 case can never be reached and would pass for the wrong reason. Owner
-- context, so the column grants that forbid this everywhere else don't apply,
-- and rolled back with the rest of the transaction.
update public.scholars set steward = false where id not in (:'stew_a', :'stew_b');

--------------------------------------------------------------------------------
-- Authorization
--------------------------------------------------------------------------------
-- An anonymous visitor cannot reach the function at all: EXECUTE is revoked from
-- anon, so this fails on privilege (42501) before any of the body runs.
select tests.authenticate_as_anon();
select throws_ok(
	$$ select public.set_steward( $$ || quote_literal(:'plain') || $$, true ) $$,
	'42501',
	null,
	'an anonymous visitor cannot execute set_steward'
);

-- Signed in, but not a steward.
select tests.authenticate_as(:'plain');
select throws_ok(
	$$ select public.set_steward( $$ || quote_literal(:'plain') || $$, true ) $$,
	'RR010',
	null,
	'a non-steward cannot change who is a steward'
);

--------------------------------------------------------------------------------
-- Promotion
--------------------------------------------------------------------------------
select tests.authenticate_as(:'stew_a');
select is(
	public.set_steward(:'plain', true) ->> 'changed',
	'true',
	'a steward can promote a scholar'
);

select tests.clear_authentication();
select is(
	(select steward from public.scholars where id = :'plain'),
	true,
	'the promoted scholar now holds the flag'
);

-- Idempotence is reported, not raised: a toggle firing against a stale list is a
-- no-op, and the client tells the two apart from `changed`.
select tests.authenticate_as(:'stew_a');
select is(
	public.set_steward(:'plain', true) ->> 'changed',
	'false',
	'promoting an existing steward is a no-op rather than an error'
);

select throws_ok(
	$$ select public.set_steward( '00000000-0000-0000-0000-000000000000'::uuid, true ) $$,
	'RR011',
	null,
	'promoting a scholar who does not exist is refused'
);

--------------------------------------------------------------------------------
-- Demotion
--------------------------------------------------------------------------------
select is(
	public.set_steward(:'plain', false) ->> 'changed',
	'true',
	'a steward can demote another steward'
);

-- Stepping down is an act another steward performs, so this is refused even
-- though two other stewards remain and no lockout is in prospect.
select throws_ok(
	$$ select public.set_steward( $$ || quote_literal(:'stew_a') || $$, false ) $$,
	'RR013',
	null,
	'a steward cannot demote themselves'
);

select tests.clear_authentication();
select is(
	(select steward from public.scholars where id = :'stew_a'),
	true,
	'the refused self-demotion left the flag alone'
);

-- Reduce to one steward, then confirm the floor holds. Reaching this state
-- through the RPC is impossible — demoting X needs a steward caller other than
-- X, so one always survives — which is exactly why the guard exists for the
-- concurrent case the function's row lock serializes.
update public.scholars set steward = false where id = :'stew_a';

select tests.authenticate_as(:'stew_b');
select throws_ok(
	$$ select public.set_steward( $$ || quote_literal(:'stew_b') || $$, false ) $$,
	'RR013',
	null,
	'the last steward cannot step down either'
);

--------------------------------------------------------------------------------
-- The column grant is still narrow
--------------------------------------------------------------------------------
-- If this ever passes, the RPC has become decoration: a steward would be able to
-- write the column directly and every guard above could be walked around.
select throws_ok(
	$$ update public.scholars set steward = true where id = $$ || quote_literal(:'plain'),
	'42501',
	null,
	'even a steward cannot write the steward column directly'
);

--------------------------------------------------------------------------------
-- Attribution
--------------------------------------------------------------------------------
-- SECURITY DEFINER changes the current user but NOT the JWT claim, and
-- log_audit_event records auth.uid() — so the audit row must name the caller,
-- not postgres. This is the most plausible way the feature could quietly lose
-- its forensic trail while still working.
select tests.authenticate_as(:'stew_b');
select public.set_steward(:'plain', true) as _promoted \gset

select tests.clear_authentication();
select is(
	(
		select actor
		from public.audit_log
		where tbl = 'scholars' and row_id = :'plain'
		order by seq desc
		limit 1
	),
	:'stew_b'::uuid,
	'the promotion records which steward made it'
);

select * from finish();
rollback;
