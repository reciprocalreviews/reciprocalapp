-- RLS tests for public.scholars.
--
-- Authorization model under test:
--   SELECT  public — visible to both anon and authenticated.
--   INSERT  blocked for everyone (check false); only the handle_new_scholar
--           auth trigger (SECURITY DEFINER) ever creates rows.
--   UPDATE  the scholar themselves or a steward.
--   DELETE  the scholar themselves only.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(11);

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();
select tests.create_scholar('sch_self@test.local') as self \gset
select tests.create_scholar('sch_steward@test.local', true) as steward \gset
select tests.create_scholar('sch_other@test.local') as other \gset
select tests.create_scholar('sch_victim@test.local') as victim \gset
select tests.create_scholar('sch_deleter@test.local') as deleter \gset

-- ---- Policy shape -------------------------------------------------------------
select policies_are(
	'public', 'scholars',
	array[
		'Scholars cannot be inserted except by platform',
		'Scholar metadata is public',
		'Scholars can be edited by stewards and selves',
		'Scholars can remove themselves'
	]
);

-- ---- SELECT (public) ----------------------------------------------------------
-- Any authenticated scholar can read any scholar row.
select tests.authenticate_as(:'other');
select isnt_empty(
	$$ select 1 from public.scholars where id = $$ || quote_literal(:'self'),
	'an authenticated scholar can read another scholar (metadata is public)'
);

-- Anonymous visitors can read scholar rows too.
select tests.authenticate_as_anon();
select isnt_empty(
	$$ select 1 from public.scholars where id = $$ || quote_literal(:'self'),
	'an anonymous visitor can read scholar metadata (metadata is public)'
);

-- ---- INSERT (blocked for everyone) --------------------------------------------
-- The policy check is `false`, so no authenticated role can insert — not even a
-- scholar inserting their own (otherwise plausible) row.
select tests.authenticate_as(:'self');
select throws_ok(
	$$ insert into public.scholars (id) values (gen_random_uuid()) $$,
	'42501',
	null,
	'an authenticated scholar cannot insert a scholar row (check false)'
);

-- A steward is equally blocked: insertion is reserved for the platform trigger.
select tests.authenticate_as(:'steward');
select throws_ok(
	$$ insert into public.scholars (id) values (gen_random_uuid()) $$,
	'42501',
	null,
	'even a steward cannot insert a scholar row (check false)'
);

-- ---- UPDATE (self or steward) -------------------------------------------------
-- A scholar may edit their own row.
select tests.authenticate_as(:'self');
select lives_ok(
	$$ update public.scholars set status = 'editing self' where id = $$ || quote_literal(:'self'),
	'a scholar can update their own row'
);

-- A steward may edit any scholar's row.
select tests.authenticate_as(:'steward');
select lives_ok(
	$$ update public.scholars set status = 'edited by steward' where id = $$ || quote_literal(:'victim'),
	'a steward can update another scholar''s row'
);
select tests.clear_authentication();
select is(
	(select status from public.scholars where id = :'victim'),
	'edited by steward',
	'the steward''s update persisted'
);

-- A non-steward editing someone else's row is filtered by the using clause:
-- 0 rows match, no error is raised, and the row is left unchanged.
select tests.authenticate_as(:'other');
update public.scholars set status = 'tampered' where id = :'victim';
select tests.clear_authentication();
select is(
	(select status from public.scholars where id = :'victim'),
	'edited by steward',
	'a non-steward cannot update another scholar''s row (no-op)'
);

-- ---- DELETE (self only) -------------------------------------------------------
-- A scholar cannot delete another scholar (using filters the row → 0 rows).
select tests.authenticate_as(:'other');
delete from public.scholars where id = :'deleter';
select tests.clear_authentication();
select is(
	(select count(*)::int from public.scholars where id = :'deleter'),
	1,
	'a scholar cannot delete another scholar (no-op)'
);

-- A scholar can remove themselves.
select tests.authenticate_as(:'deleter');
select lives_ok(
	$$ delete from public.scholars where id = $$ || quote_literal(:'deleter'),
	'a scholar can delete their own row'
);

select * from finish();
rollback;
