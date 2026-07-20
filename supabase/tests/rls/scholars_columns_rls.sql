-- Column-level privileges on public.scholars.
--
-- The row-level policies are covered in scholars_rls.sql; this file covers WHICH COLUMNS
-- a scholar may write. That distinction is load-bearing and was previously untested: the
-- update policy authorizes the row and says nothing about columns, so while `grant all`
-- stood, a scholar could self-promote to steward, claim another researcher's ORCID iD, or
-- set their contact email directly and skip verification (#27) — all while every
-- row-level test still passed.
--
-- See supabase/migrations/20260719010000_scholars_column_privileges.sql.

\ir ../_helpers/helpers.sql.inc

begin;

create extension if not exists pgtap
with
	schema extensions;

select
	plan (8);

select
	tests.create_scholar ('columns_self@test.local') as self \gset

select
	tests.create_scholar ('columns_other@test.local') as other \gset

select
	tests.create_scholar ('columns_steward@test.local', true) as steward \gset

-- ---- Permitted columns ---------------------------------------------------------
select
	tests.authenticate_as (:'self');

select
	lives_ok (
		$$ update public.scholars set name = 'Renamed' where id = $$ || quote_literal(:'self'),
		'a scholar can update their own name'
	);

select
	lives_ok (
		$$ update public.scholars set available = false, status = 'on leave', status_time = now() where id = $$ || quote_literal(:'self'),
		'a scholar can update their own availability and status'
	);

-- ---- Denied columns ------------------------------------------------------------
-- These are permission errors (42501), not silent no-ops: the column privilege is
-- absent, so Postgres rejects the statement before RLS filtering applies.
select
	throws_ok (
		$$ update public.scholars set steward = true where id = $$ || quote_literal(:'self'),
		'42501',
		null,
		'a scholar cannot promote themselves to steward'
	);

select
	throws_ok (
		$$ update public.scholars set email = 'unverified@evil.invalid' where id = $$ || quote_literal(:'self'),
		'42501',
		null,
		'a scholar cannot set their contact email directly, bypassing verification'
	);

select
	throws_ok (
		$$ update public.scholars set orcid = '0000-0002-1825-0097' where id = $$ || quote_literal(:'self'),
		'42501',
		null,
		'a scholar cannot rewrite their ORCID iD'
	);

-- A steward is equally restricted: column grants are role-wide, and nothing in the app
-- edits another scholar's identity columns.
select
	tests.authenticate_as (:'steward');

select
	throws_ok (
		$$ update public.scholars set steward = true where id = $$ || quote_literal(:'other'),
		'42501',
		null,
		'even a steward cannot grant steward status by direct update'
	);

select
	throws_ok (
		$$ update public.scholars set email = 'unverified@evil.invalid' where id = $$ || quote_literal(:'other'),
		'42501',
		null,
		'even a steward cannot set another scholar''s contact email directly'
	);

-- ---- ORCID uniqueness ----------------------------------------------------------
-- One iD identifies one scholar (#87). Asserted as the platform (owner) because
-- scholars rows are inserted only by the handle_new_scholar trigger.
select
	tests.clear_authentication ();

update public.scholars
set
	orcid = '0000-0002-1825-0097'
where
	id = :'self';

select
	throws_ok (
		$$ update public.scholars set orcid = '0000-0002-1825-0097' where id = $$ || quote_literal(:'other'),
		'23505',
		null,
		'two scholars cannot share an ORCID iD'
	);

select
	*
from
	finish ();

rollback;
