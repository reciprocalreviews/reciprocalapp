-- RPC tests for public.remove_volunteer: a venue's admins and its top-priority role marking
-- another scholar's volunteer record inactive.
--
-- What is under test:
--   WHO      venue admins and accepted holders of the priority-0 role may; other volunteers,
--            anonymous callers and the volunteer themselves may not.
--   WHAT     only accepted records, and only by deactivating: the row survives, so the
--            welcome grant stays one-time, and the volunteer may resume afterwards.
--   NOTICE   one consequential RoleRemoved email to the volunteer per removal.
--
-- The send_on_email_insert trigger is disabled for this rolled-back test, as in
-- new_volunteer_notice.sql: nothing here depends on mail actually being dispatched.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan (14);

alter table public.emails disable trigger send_on_email_insert;

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();

select tests.create_scholar('rv_minter@test.local')   as minter   \gset
select tests.create_scholar('rv_admin@test.local')    as admin    \gset
select tests.create_scholar('rv_editor@test.local')   as editor   \gset
select tests.create_scholar('rv_peer@test.local')     as peer     \gset
select tests.create_scholar('rv_target@test.local')   as target   \gset
select tests.create_scholar('rv_second@test.local')   as second   \gset
select tests.create_scholar('rv_invitee@test.local')  as invitee  \gset

select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as ven \gset

select tests.create_role(:'ven', 0, null, false, true)  as toprole \gset
select tests.create_role(:'ven', 1, null, false, false) as revrole \gset

select tests.create_volunteer(:'editor', :'toprole') as veditor \gset
select tests.create_volunteer(:'peer', :'revrole')   as vpeer   \gset
select tests.create_volunteer(:'target', :'revrole') as vtarget \gset
select tests.create_volunteer(:'second', :'revrole') as vsecond \gset
select tests.create_volunteer(:'invitee', :'revrole', 'invited') as vinvitee \gset

-- ---- Who may not ---------------------------------------------------------------
select tests.authenticate_as_anon();
select throws_ok(
	format('select public.remove_volunteer(%L)', :'vtarget'),
	'42501',
	null,
	'anonymous callers cannot remove volunteers'
);

select tests.authenticate_as(:'peer');
select throws_ok(
	format('select public.remove_volunteer(%L)', :'vtarget'),
	'Only venue admins and the top role may remove volunteers',
	'a volunteer in an ordinary role cannot remove another'
);

select tests.authenticate_as(:'editor');
select throws_ok(
	format('select public.remove_volunteer(%L)', :'veditor'),
	'Stop volunteering instead of removing yourself',
	'nobody removes themselves'
);
select throws_ok(
	format('select public.remove_volunteer(%L)', :'vinvitee'),
	'Only accepted volunteers can be removed',
	'an unanswered invitation cannot be removed'
);

-- ---- Who may -------------------------------------------------------------------
select lives_ok(
	format('select public.remove_volunteer(%L)', :'vtarget'),
	'a holder of the top role removes a volunteer'
);

select tests.authenticate_as(:'admin');
select lives_ok(
	format('select public.remove_volunteer(%L)', :'vsecond'),
	'a venue admin removes a volunteer'
);
-- Removing someone already inactive changes nothing and tells nobody again.
select is(
	public.remove_volunteer(:'vsecond') ->> 'notified',
	'false',
	'removing an inactive volunteer again sends nothing'
);

-- ---- What happened -------------------------------------------------------------
select tests.clear_authentication();
select is(
	(select active from public.volunteers where id = :'vtarget'),
	false,
	'the removed volunteer is inactive'
);
select is(
	(select count(*)::integer from public.volunteers where id in (:'vtarget', :'vsecond')),
	2,
	'removal keeps the volunteer records'
);
select is(
	(select count(*)::integer from public.emails where event = 'RoleRemoved' and scholar = :'target'),
	1,
	'the removed volunteer is emailed once'
);
select is(
	(select count(*)::integer from public.emails where event = 'RoleRemoved' and scholar = :'second'),
	1,
	'a repeated removal does not email twice'
);
select is(
	(select args ->> 0 from public.emails where event = 'RoleRemoved' and scholar = :'target'),
	(select name from public.roles where id = :'revrole'),
	'the notice names the role'
);

-- ---- And may come back ---------------------------------------------------------
select tests.authenticate_as(:'target');
update public.volunteers set active = true where id = :'vtarget';
select tests.clear_authentication();
select is(
	(select active from public.volunteers where id = :'vtarget'),
	true,
	'a removed volunteer can resume'
);

select ok(
	not has_function_privilege('anon', 'public.remove_volunteer(uuid)', 'execute'),
	'anon has no EXECUTE on remove_volunteer'
);

select * from finish();
rollback;
