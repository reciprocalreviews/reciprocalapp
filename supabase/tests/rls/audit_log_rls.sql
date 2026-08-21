-- RLS and append-only tests for public.audit_log.
--
-- Authorization model under test:
--   SELECT  nobody through the API. The payloads are whole rows, so this table
--           holds scholars' contact emails and the bodies of author thank-you
--           notes — strictly more sensitive than any single table it records.
--   INSERT  only the logging trigger (SECURITY DEFINER, runs as the owner).
--   UPDATE  refused, except erasure rewriting the payloads and the actor.
--   DELETE  refused, always.
--
-- As with token_events, the refusals are enforced by a TRIGGER and exercised here
-- as the OWNER, because `postgres` and `service_role` bypass RLS and are exactly
-- who would be at the keyboard during an incident.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(7);

select tests.clear_authentication();
select tests.create_scholar('alr_minter@test.local') as minter \gset
select tests.create_scholar('alr_admin@test.local') as admin \gset
select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as ven \gset

select seq as ev_seq
from public.audit_log
where tbl = 'venues' and row_id = :'ven'
order by seq desc
limit 1 \gset

-- ---- Policy shape -------------------------------------------------------------
select policies_are('public', 'audit_log', array[]::text[]);

-- ---- SELECT -------------------------------------------------------------------
-- Revoked at the privilege level, so these fail closed with 42501 rather than
-- quietly returning nothing. A revoked privilege cannot be re-opened by someone
-- adding a well-meaning policy later.
select tests.authenticate_as(:'admin');
select throws_ok(
	$$ select 1 from public.audit_log $$,
	'42501',
	null,
	'an authenticated scholar cannot read the audit log'
);

select tests.authenticate_as_anon();
select throws_ok(
	$$ select 1 from public.audit_log $$,
	'42501',
	null,
	'anonymous visitors cannot read the audit log'
);

-- ---- Append-only, as the OWNER ------------------------------------------------
select tests.clear_authentication();
select throws_ok(
	$$ delete from public.audit_log where seq = $$ || :'ev_seq',
	'P0001',
	'public.audit_log is append-only; rows are never deleted',
	'not even the owner can delete an audit row'
);

select throws_ok(
	$$ update public.audit_log set after = '{}'::jsonb where seq = $$ || :'ev_seq',
	'P0001',
	'public.audit_log is append-only',
	'not even the owner can rewrite an audit row'
);

-- ---- Erasure ------------------------------------------------------------------
-- A scholar's name and contact email reach this table inside the payloads, so
-- erasure must be able to scrub them — while leaving which table changed, when,
-- and in what order untouched.
select lives_ok(
	$$ set local app.erasure = 'on';
	   update public.audit_log
	   set before = null, after = null, actor = null
	   where seq = $$ || :'ev_seq',
	'erasure may scrub the payloads and the actor'
);

select throws_ok(
	$$ set local app.erasure = 'on';
	   update public.audit_log set tbl = 'something_else' where seq = $$ || :'ev_seq',
	'P0001',
	'erasure may only rewrite before, after, and actor',
	'erasure cannot rewrite which table changed'
);

select * from finish();
rollback;
