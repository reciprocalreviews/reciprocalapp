-- RLS tests for public.roles.
--
-- Authorization model under test:
--   SELECT  public — any authenticated scholar or anonymous visitor.
--   INSERT  venue admins only (with check isAdmin(venueid)).
--   UPDATE  venue admins only (using isAdmin(venueid)).
--   DELETE  venue admins only (using isAdmin(venueid)).

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();
select tests.create_scholar('roles_admin@test.local') as admin \gset
select tests.create_scholar('roles_minter@test.local') as minter \gset
select tests.create_scholar('roles_outsider@test.local') as outsider \gset
-- A second venue with a different admin, to prove admin rights are venue-scoped.
select tests.create_scholar('roles_otheradmin@test.local') as otheradmin \gset
select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
-- admins must NOT overlap currency minters (no_minter_admins trigger).
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as ven \gset
select tests.create_venue(:'cur', array[:'otheradmin']::uuid[]) as other_ven \gset

-- An existing role in the venue, used by the SELECT/UPDATE/DELETE probes.
select tests.create_role(:'ven', 0) as role \gset
-- A role used specifically for the DELETE positive case.
select tests.create_role(:'ven', 0) as role_del \gset

-- ---- Policy shape -------------------------------------------------------------
select policies_are(
	'public', 'roles',
	array[
		'anyone can view roles',
		'only admins can create venue roles',
		'only admins can update roles',
		'only admins can delete roles'
	]
);

-- ---- SELECT -------------------------------------------------------------------
-- Roles are public: any authenticated scholar can see them.
select tests.authenticate_as(:'outsider');
select isnt_empty(
	$$ select 1 from public.roles where id = $$ || quote_literal(:'role'),
	'any authenticated scholar can view a role'
);

-- Roles are public: anonymous visitors can see them too.
select tests.authenticate_as_anon();
select isnt_empty(
	$$ select 1 from public.roles where id = $$ || quote_literal(:'role'),
	'anonymous visitors can view a role'
);

-- ---- INSERT -------------------------------------------------------------------
-- A venue admin can create a role in their venue.
select tests.authenticate_as(:'admin');
select lives_ok(
	$$ insert into public.roles (venueid, name, invited, biddable, priority)
	   values ( $$ || quote_literal(:'ven') || $$, 'Reviewer', false, false, 0) $$,
	'a venue admin can create a role in their venue'
);

-- A non-admin scholar cannot create a role (with check → throws 42501).
select tests.authenticate_as(:'outsider');
select throws_ok(
	$$ insert into public.roles (venueid, name, invited, biddable, priority)
	   values ( $$ || quote_literal(:'ven') || $$, 'Sneaky', false, false, 0) $$,
	'42501',
	null,
	'a non-admin scholar cannot create a role'
);

-- An admin of a DIFFERENT venue cannot create a role in this venue.
select tests.authenticate_as(:'otheradmin');
select throws_ok(
	$$ insert into public.roles (venueid, name, invited, biddable, priority)
	   values ( $$ || quote_literal(:'ven') || $$, 'Cross-venue', false, false, 0) $$,
	'42501',
	null,
	'an admin of another venue cannot create a role here'
);

-- ---- UPDATE -------------------------------------------------------------------
-- A venue admin can update a role in their venue.
select tests.authenticate_as(:'admin');
select lives_ok(
	$$ update public.roles set name = 'Renamed' where id = $$ || quote_literal(:'role'),
	'a venue admin can update a role'
);
select tests.clear_authentication();
select is(
	(select name from public.roles where id = :'role'),
	'Renamed',
	'the role name is now updated'
);

-- A non-admin scholar cannot update — using clause filters the row (0 rows, no error).
select tests.authenticate_as(:'outsider');
update public.roles set name = 'Hijacked' where id = :'role';
select tests.clear_authentication();
select is(
	(select name from public.roles where id = :'role'),
	'Renamed',
	'a non-admin scholar cannot update a role (no-op)'
);

-- An admin of a different venue cannot update — using clause filters the row.
select tests.authenticate_as(:'otheradmin');
update public.roles set name = 'Cross' where id = :'role';
select tests.clear_authentication();
select is(
	(select name from public.roles where id = :'role'),
	'Renamed',
	'an admin of another venue cannot update a role here (no-op)'
);

-- ---- DELETE -------------------------------------------------------------------
-- A non-admin scholar cannot delete — using clause filters the row (0 rows, no error).
select tests.authenticate_as(:'outsider');
delete from public.roles where id = :'role_del';
select tests.clear_authentication();
select is(
	(select count(*)::int from public.roles where id = :'role_del'),
	1,
	'a non-admin scholar cannot delete a role'
);

-- A venue admin can delete a role in their venue.
select tests.authenticate_as(:'admin');
select lives_ok(
	$$ delete from public.roles where id = $$ || quote_literal(:'role_del'),
	'a venue admin can delete a role'
);

select * from finish();
rollback;
