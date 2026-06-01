-- RLS tests for public.proposals.
--
-- Authorization model under test:
--   SELECT  anyone — authenticated scholars and anonymous visitors.
--   INSERT  any authenticated scholar may propose a venue (anon cannot).
--   UPDATE  stewards only (USING isSteward()).
--   DELETE  stewards only (USING isSteward()).

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(10);

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();
select tests.create_scholar('prop_steward@test.local', true) as steward \gset
select tests.create_scholar('prop_scholar@test.local') as scholar \gset

-- A proposal to update / delete. Inserted in owner context (bypasses RLS).
-- census is NOT NULL with no default.
insert into public.proposals (title, url, editors, minters, census)
values ('Existing Proposal', 'https://example.test', '{}'::text[], '{}'::text[], 100)
returning id as prop \gset

-- ---- Policy shape -------------------------------------------------------------
select policies_are(
	'public', 'proposals',
	array[
		'anyone can view proposals',
		'anyone can propose venues',
		'admins can update proposals',
		'admins can delete proposals'
	]
);

-- ---- SELECT -------------------------------------------------------------------
select tests.authenticate_as(:'scholar');
select isnt_empty(
	$$ select 1 from public.proposals where id = $$ || quote_literal(:'prop'),
	'an authenticated scholar can view proposals'
);

select tests.authenticate_as_anon();
select isnt_empty(
	$$ select 1 from public.proposals where id = $$ || quote_literal(:'prop'),
	'an anonymous visitor can view proposals'
);

-- ---- INSERT -------------------------------------------------------------------
-- Any authenticated scholar may propose a venue (with check is true).
select tests.authenticate_as(:'scholar');
select lives_ok(
	$$ insert into public.proposals (title, url, editors, minters, census)
	   values ('Proposed Venue', 'https://proposed.test', '{}'::text[], '{}'::text[], 50) $$,
	'an authenticated scholar can propose a venue'
);

-- An anonymous visitor has no INSERT policy → denied.
select tests.authenticate_as_anon();
select throws_ok(
	$$ insert into public.proposals (title, url, editors, minters, census)
	   values ('Anon Proposal', 'https://anon.test', '{}'::text[], '{}'::text[], 10) $$,
	'42501',
	null,
	'an anonymous visitor cannot propose a venue'
);

-- ---- UPDATE -------------------------------------------------------------------
-- A steward may update any proposal.
select tests.authenticate_as(:'steward');
select lives_ok(
	$$ update public.proposals set title = 'Edited By Steward' where id = $$ || quote_literal(:'prop'),
	'a steward can update a proposal'
);
select tests.clear_authentication();
select is(
	(select title from public.proposals where id = :'prop'),
	'Edited By Steward',
	'the proposal now reflects the steward edit'
);

-- A non-steward's UPDATE is filtered by the using clause (0 rows, no error).
select tests.authenticate_as(:'scholar');
update public.proposals set title = 'Tampered' where id = :'prop';
select tests.clear_authentication();
select is(
	(select title from public.proposals where id = :'prop'),
	'Edited By Steward',
	'a non-steward cannot update a proposal (no-op)'
);

-- ---- DELETE -------------------------------------------------------------------
-- A non-steward cannot delete (using = stewards only → 0 rows, no error).
select tests.authenticate_as(:'scholar');
delete from public.proposals where id = :'prop';
select tests.clear_authentication();
select is(
	(select count(*)::int from public.proposals where id = :'prop'),
	1,
	'a non-steward cannot delete a proposal'
);

-- A steward can delete a proposal.
select tests.authenticate_as(:'steward');
select lives_ok(
	$$ delete from public.proposals where id = $$ || quote_literal(:'prop'),
	'a steward can delete a proposal'
);

select * from finish();
rollback;
