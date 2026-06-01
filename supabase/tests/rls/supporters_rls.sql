-- RLS tests for public.supporters.
--
-- Authorization model under test:
--   SELECT  public — any authenticated scholar or anonymous visitor may read.
--   INSERT  any authenticated scholar may support a proposal (check is true, so a
--           scholar may even record support naming another scholar's id).
--   UPDATE  self only — a scholar may edit a support row only when
--           auth.uid() = scholarid (using clause); others are filtered out.
--   DELETE  self only — a scholar may stop supporting only their own row;
--           others are filtered out.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(11);

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();
select tests.create_scholar('sup_owner@test.local') as owner \gset
select tests.create_scholar('sup_other@test.local') as other \gset

-- A proposal to support (no dedicated builder; insert directly as owner).
-- census is NOT NULL with no default, so it must be supplied.
insert into public.proposals (title, census)
values ('Test Proposal', 100)
returning id as prop \gset

-- A support row owned by :owner, used for the SELECT/UPDATE/DELETE probes.
insert into public.supporters (scholarid, proposalid, message)
values (:'owner', :'prop', 'I support this')
returning id as sup \gset

-- A second support row owned by :owner, reserved for the DELETE probes so the
-- UPDATE probes leave it untouched.
insert into public.supporters (scholarid, proposalid, message)
values (:'owner', :'prop', 'still supporting')
returning id as sup_del \gset

-- ---- Policy shape -------------------------------------------------------------
select policies_are(
	'public', 'supporters',
	array[
		'anyone can view supporters',
		'anyone can support proposals',
		'supporters can update their own support',
		'supporters can stop supporting'
	]
);

-- ---- SELECT (public: every authenticated scholar + anon may read) -------------
select tests.authenticate_as(:'owner');
select isnt_empty(
	$$ select 1 from public.supporters where id = $$ || quote_literal(:'sup'),
	'the supporting scholar can see their own support'
);

select tests.authenticate_as(:'other');
select isnt_empty(
	$$ select 1 from public.supporters where id = $$ || quote_literal(:'sup'),
	'an unrelated authenticated scholar can see the support'
);

select tests.authenticate_as_anon();
select isnt_empty(
	$$ select 1 from public.supporters where id = $$ || quote_literal(:'sup'),
	'an anonymous visitor can see the support'
);

-- ---- INSERT -------------------------------------------------------------------
-- Any authenticated scholar may support (check is true).
select tests.authenticate_as(:'other');
select lives_ok(
	$$ insert into public.supporters (scholarid, proposalid, message)
	   values ( $$ || quote_literal(:'other') || $$, $$ || quote_literal(:'prop') || $$, 'me too') $$,
	'an authenticated scholar can support a proposal'
);

-- An anonymous visitor cannot insert (INSERT policy is authenticated-only).
select tests.authenticate_as_anon();
select throws_ok(
	$$ insert into public.supporters (scholarid, proposalid, message)
	   values ( $$ || quote_literal(:'owner') || $$, $$ || quote_literal(:'prop') || $$, 'anon support') $$,
	'42501',
	null,
	'an anonymous visitor cannot support a proposal'
);

-- ---- UPDATE -------------------------------------------------------------------
-- The owning scholar may edit their own support row.
select tests.authenticate_as(:'owner');
select lives_ok(
	$$ update public.supporters set message = 'edited by owner' where id = $$ || quote_literal(:'sup'),
	'a scholar can update their own support'
);
select tests.clear_authentication();
select is(
	(select message from public.supporters where id = :'sup'),
	'edited by owner',
	'the owner''s edit was applied'
);

-- A different authenticated scholar is filtered by the using clause (0 rows, no
-- error) — the row is left unchanged.
select tests.authenticate_as(:'other');
update public.supporters set message = 'tampered' where id = :'sup';
select tests.clear_authentication();
select is(
	(select message from public.supporters where id = :'sup'),
	'edited by owner',
	'an unrelated scholar cannot update another scholar''s support (no-op)'
);

-- ---- DELETE -------------------------------------------------------------------
-- A different authenticated scholar is filtered by the using clause (0 rows, no
-- error) — the row is still present.
select tests.authenticate_as(:'other');
delete from public.supporters where id = :'sup_del';
select tests.clear_authentication();
select is(
	(select count(*)::int from public.supporters where id = :'sup_del'),
	1,
	'an unrelated scholar cannot delete another scholar''s support'
);

-- The owning scholar may stop supporting (delete their own row).
select tests.authenticate_as(:'owner');
select lives_ok(
	$$ delete from public.supporters where id = $$ || quote_literal(:'sup_del'),
	'a scholar can delete their own support'
);

select * from finish();
rollback;
