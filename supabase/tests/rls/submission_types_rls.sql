-- RLS tests for public.submission_types.
--
-- Authorization model under test:
--   SELECT  public — anyone (anon + authenticated) may read submission types.
--   INSERT  venue admins only (isAdmin(venue)).
--   UPDATE  venue admins only (isAdmin(venue)); with check (true).
--   DELETE  venue admins only (isAdmin(venue)).

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(13);

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();
select tests.create_scholar('st_minter@test.local') as minter \gset
select tests.create_scholar('st_admin@test.local') as admin \gset
select tests.create_scholar('st_outsider@test.local') as outsider \gset
-- A second, unrelated venue (with its own admin) to prove cross-venue isolation.
select tests.create_scholar('st_other_admin@test.local') as other_admin \gset

-- admins must NOT overlap the currency's minters (no_minter_admins trigger).
select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as ven \gset
select tests.create_venue(:'cur', array[:'other_admin']::uuid[]) as other_ven \gset

-- An existing submission type at the target venue (used by SELECT/UPDATE/DELETE).
select tests.create_submission_type(:'ven') as styp \gset
-- A submission type used specifically by the DELETE tests.
select tests.create_submission_type(:'ven') as styp_del \gset

-- ---- Policy shape -------------------------------------------------------------
select policies_are(
	'public', 'submission_types',
	array[
		'venue admins can create submission types',
		'anyone can read submission types',
		'venue admins can update submission types',
		'venue admins can delete submission types'
	]
);

-- ---- SELECT (public) ----------------------------------------------------------
select tests.authenticate_as(:'admin');
select isnt_empty(
	$$ select 1 from public.submission_types where id = $$ || quote_literal(:'styp'),
	'a venue admin can read submission types'
);

select tests.authenticate_as(:'outsider');
select isnt_empty(
	$$ select 1 from public.submission_types where id = $$ || quote_literal(:'styp'),
	'an unrelated scholar can read submission types'
);

select tests.authenticate_as_anon();
select isnt_empty(
	$$ select 1 from public.submission_types where id = $$ || quote_literal(:'styp'),
	'an anonymous visitor can read submission types'
);

-- ---- INSERT (venue admins) ----------------------------------------------------
-- A venue admin may create a submission type for their venue.
select tests.authenticate_as(:'admin');
select lives_ok(
	$$ insert into public.submission_types (venue, name)
	   values ( $$ || quote_literal(:'ven') || $$, 'admin made this' ) $$,
	'a venue admin can create a submission type for their venue'
);

-- A non-admin scholar cannot create a submission type (with check fails → 42501).
select tests.authenticate_as(:'outsider');
select throws_ok(
	$$ insert into public.submission_types (venue, name)
	   values ( $$ || quote_literal(:'ven') || $$, 'outsider made this' ) $$,
	'42501',
	null,
	'an unrelated scholar cannot create a submission type'
);

-- An admin of a different venue cannot create a type for this venue (42501).
select tests.authenticate_as(:'other_admin');
select throws_ok(
	$$ insert into public.submission_types (venue, name)
	   values ( $$ || quote_literal(:'ven') || $$, 'cross venue insert' ) $$,
	'42501',
	null,
	'an admin of another venue cannot create a submission type here'
);

-- An anonymous visitor cannot create a submission type (insert policy is
-- authenticated-only → no permissive policy applies → 42501).
select tests.authenticate_as_anon();
select throws_ok(
	$$ insert into public.submission_types (venue, name)
	   values ( $$ || quote_literal(:'ven') || $$, 'anon made this' ) $$,
	'42501',
	null,
	'an anonymous visitor cannot create a submission type'
);

-- ---- UPDATE (venue admins) ----------------------------------------------------
-- A venue admin may update a submission type for their venue.
select tests.authenticate_as(:'admin');
select lives_ok(
	$$ update public.submission_types set name = 'renamed by admin' where id = $$ || quote_literal(:'styp'),
	'a venue admin can update a submission type for their venue'
);
select tests.clear_authentication();
select is(
	(select name from public.submission_types where id = :'styp'),
	'renamed by admin',
	'the submission type now reflects the admin edit'
);

-- A non-admin's UPDATE is filtered by the using clause (0 rows, no error).
select tests.authenticate_as(:'outsider');
update public.submission_types set name = 'tampered' where id = :'styp';
select tests.clear_authentication();
select is(
	(select name from public.submission_types where id = :'styp'),
	'renamed by admin',
	'an unrelated scholar cannot update a submission type (no-op)'
);

-- ---- DELETE (venue admins) ----------------------------------------------------
-- A non-admin's DELETE is filtered by the using clause (0 rows, no error).
select tests.authenticate_as(:'outsider');
delete from public.submission_types where id = :'styp_del';
select tests.clear_authentication();
select is(
	(select count(*)::int from public.submission_types where id = :'styp_del'),
	1,
	'an unrelated scholar cannot delete a submission type'
);

-- A venue admin can delete a submission type for their venue.
select tests.authenticate_as(:'admin');
select lives_ok(
	$$ delete from public.submission_types where id = $$ || quote_literal(:'styp_del'),
	'a venue admin can delete a submission type for their venue'
);

select * from finish();
rollback;
