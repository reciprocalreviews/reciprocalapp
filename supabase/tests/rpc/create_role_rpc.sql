-- Tests for create_role, defined in migration 20260828030000_role_priority.sql.
--
-- roles.priority defaults to 0, and priority 0 is an authorization predicate, not a
-- display detail: public.isPriorityZero(), public.can_approve_assignment(), the
-- submissions author-list lock and public.mark_submission_done() all key on it. Creating
-- roles with a plain insert therefore made every new role an editor role. This RPC exists
-- to give each new role a priority of its own, and these tests are the safety net for
-- that — including the assertion that it did NOT become a way around the insert policy.
--
-- Unlike the SECURITY DEFINER RPCs, this one is SECURITY INVOKER, so an unauthorized
-- caller is refused by RLS itself: SQLSTATE 42501, not P0001.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

-- ---- Fixtures (owner context) ------------------------------------------------
select tests.clear_authentication();
select tests.create_scholar('cr_minter@test.local') as minter \gset
select tests.create_scholar('cr_admin@test.local') as admin \gset
select tests.create_scholar('cr_outsider@test.local') as outsider \gset

-- Two venues, so the "bottom of the order" is per venue rather than global. Admins must
-- not overlap the currency's minters (the no_minter_admins trigger enforces that).
select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as ven \gset
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as ven2 \gset

--------------------------------------------------------------------------------
-- Priority assignment
--------------------------------------------------------------------------------
select tests.authenticate_as(:'admin');

-- A venue's first role lands at 0, which is what proposal approval relies on for the
-- default Editor role it creates.
select is(
	(select priority from public.create_role(:'ven', 'Editor', 'Decides.')),
	0,
	'the first role at a venue gets priority 0'
);

select is(
	(select priority from public.create_role(:'ven', 'Associate Editor', '')),
	1,
	'the second role goes to the bottom rather than tying at 0'
);

select is(
	(select priority from public.create_role(:'ven', 'Reviewer', '')),
	2,
	'the third role goes below the second'
);

-- The whole point: exactly one role per venue carries editor authority.
select is(
	(select count(*)::int from public.roles where venueid = :'ven' and priority = 0),
	1,
	'only one role at the venue has priority 0'
);

select is(
	(select count(distinct priority)::int from public.roles where venueid = :'ven'),
	3,
	'no two roles at the venue share a priority'
);

-- Priorities are per venue, so a second venue starts its own numbering at 0.
select is(
	(select priority from public.create_role(:'ven2', 'Editor', '')),
	0,
	'a different venue starts its own numbering at 0'
);

-- The returned row is the role that was actually created, which is what the client
-- relies on to seed the new role's invite field.
select is(
	(select name from public.create_role(:'ven2', 'Reviewer', 'Reviews.')),
	'Reviewer',
	'the function returns the role it created'
);

--------------------------------------------------------------------------------
-- Authorization is still the insert policy's job
--------------------------------------------------------------------------------
-- security invoker means "only admins can create venue roles" applies unchanged; a
-- non-admin is refused by RLS (42501) rather than by anything in the function.
select tests.authenticate_as(:'outsider');
select throws_ok(
	$$ select public.create_role( $$ || quote_literal(:'ven') || $$, 'Sneaky', '') $$,
	'42501',
	null,
	'a non-admin cannot create a role through the RPC'
);

select tests.clear_authentication();
select is(
	(select count(*)::int from public.roles where venueid = :'ven' and name = 'Sneaky'),
	0,
	'the refused role was not created'
);

select * from finish();
rollback;
