-- RLS tests for public.preference_levels.
--
-- Authorization model under test:
--   SELECT  authenticated scholars only (any signed-in scholar may read);
--           anonymous visitors cannot read.
--   INSERT  venue admins only (isAdmin(venueid)).
--   UPDATE  venue admins only (isAdmin(venueid)).
--   DELETE  venue admins only (isAdmin(venueid)).

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();
-- admin and minter must be DISTINCT scholars: a venue's admins must not overlap
-- its currency's minters (no_minter_admins / no_admin_minters triggers).
select tests.create_scholar('pref_minter@test.local') as minter \gset
select tests.create_scholar('pref_admin@test.local') as admin \gset
select tests.create_scholar('pref_outsider@test.local') as outsider \gset
select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as ven \gset

-- A preference level to read/update/delete (owner context, bypasses RLS).
insert into public.preference_levels (venueid, label, rank)
values (:'ven', 'Preferred', 0)
returning id as pref \gset

-- A second level used for the delete tests.
insert into public.preference_levels (venueid, label, rank)
values (:'ven', 'If necessary', 1)
returning id as pref_del \gset

-- ---- Policy shape -------------------------------------------------------------
select policies_are(
	'public', 'preference_levels',
	array[
		'authenticated scholars can view preference levels',
		'only admins can create preference levels',
		'only admins can update preference levels',
		'only admins can delete preference levels'
	]
);

-- ---- SELECT -------------------------------------------------------------------
-- Any authenticated scholar (even an unrelated outsider) may read.
select tests.authenticate_as(:'outsider');
select isnt_empty(
	$$ select 1 from public.preference_levels where id = $$ || quote_literal(:'pref'),
	'an authenticated scholar can view a preference level'
);

-- Anonymous visitors cannot read (policy is to authenticated only).
select tests.authenticate_as_anon();
select is_empty(
	$$ select 1 from public.preference_levels where id = $$ || quote_literal(:'pref'),
	'anonymous visitors cannot view preference levels'
);

-- ---- INSERT -------------------------------------------------------------------
-- A venue admin may create a preference level (with check = isAdmin(venueid)).
select tests.authenticate_as(:'admin');
select lives_ok(
	$$ insert into public.preference_levels (venueid, label, rank)
	   values ( $$ || quote_literal(:'ven') || $$, 'No', 2) $$,
	'a venue admin can create a preference level'
);

-- A non-admin is denied by the with-check clause.
select tests.authenticate_as(:'outsider');
select throws_ok(
	$$ insert into public.preference_levels (venueid, label, rank)
	   values ( $$ || quote_literal(:'ven') || $$, 'Sneaky', 3) $$,
	'42501',
	null,
	'a non-admin cannot create a preference level'
);

-- ---- UPDATE -------------------------------------------------------------------
-- A venue admin may update a preference level.
select tests.authenticate_as(:'admin');
select lives_ok(
	$$ update public.preference_levels set label = 'Strongly preferred'
	   where id = $$ || quote_literal(:'pref'),
	'a venue admin can update a preference level'
);

-- A non-admin's UPDATE is filtered by the using clause (0 rows, no error).
select tests.authenticate_as(:'outsider');
update public.preference_levels set label = 'Tampered' where id = :'pref';
select tests.clear_authentication();
select is(
	(select label from public.preference_levels where id = :'pref'),
	'Strongly preferred',
	'a non-admin cannot update a preference level (no-op)'
);

-- ---- DELETE -------------------------------------------------------------------
-- A non-admin's DELETE is filtered by the using clause (0 rows, no error).
select tests.authenticate_as(:'outsider');
delete from public.preference_levels where id = :'pref_del';
select tests.clear_authentication();
select is(
	(select count(*)::int from public.preference_levels where id = :'pref_del'),
	1,
	'a non-admin cannot delete a preference level'
);

-- A venue admin can delete a preference level.
select tests.authenticate_as(:'admin');
select lives_ok(
	$$ delete from public.preference_levels where id = $$ || quote_literal(:'pref_del'),
	'a venue admin can delete a preference level'
);

select * from finish();
rollback;
