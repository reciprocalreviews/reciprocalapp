-- RPC tests for public.add_to_role: the invite form's "They already agreed" path.
--
-- What is under test:
--   STAFF    only whoever staffs the role (can_staff_role) may add people to it. A holder of
--            the venue's top role who is not an admin may.
--   SEAT     someone with no record is seated; an unanswered invitation is accepted on the
--            person's behalf, with the first-role welcome grant only when it is their first
--            role at the venue; everyone seated is emailed RoleEnrolled.
--   REFUSE   a declined invitation (RR027), an accepted record (RR004), a paused record
--            (RR004, and it stays paused), and an empty list.
--   ATOMIC   a refusal anywhere in the list seats nobody.
--
-- The send_on_email_insert trigger is disabled for this rolled-back test, as in
-- new_volunteer_notice.sql: nothing here depends on mail actually being dispatched.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan (17);

alter table public.emails disable trigger send_on_email_insert;

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();

select tests.create_scholar('atr_minter@test.local')   as minter   \gset
select tests.create_scholar('atr_admin@test.local')    as admin    \gset
select tests.create_scholar('atr_editor@test.local')   as editor   \gset
select tests.create_scholar('atr_outsider@test.local') as outsider \gset
select tests.create_scholar('atr_invitee@test.local')  as invitee  \gset
select tests.create_scholar('atr_veteran@test.local')  as veteran  \gset
select tests.create_scholar('atr_newbie@test.local')   as newbie   \gset
select tests.create_scholar('atr_decliner@test.local') as decliner \gset
select tests.create_scholar('atr_member@test.local')   as member   \gset
select tests.create_scholar('atr_paused@test.local')   as paused   \gset

select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'admin']::uuid[], 5) as ven \gset

select tests.create_role(:'ven', 0, null, false, false) as roleeditor \gset
select tests.create_role(:'ven', 1, null, false, true) as rolereviewer \gset
select tests.create_role(:'ven', 2, null, false, false) as roleother \gset

-- The editor holds the top role, which is what lets them staff every role at the venue.
select tests.create_volunteer(:'editor', :'roleeditor');

-- Invited and silent; their only record at the venue, so accepting earns the welcome grant.
select tests.create_volunteer(:'invitee', :'rolereviewer', 'invited');
-- Invited and silent, but already serving in another role here: no second welcome grant.
select tests.create_volunteer(:'veteran', :'rolereviewer', 'invited');
select tests.create_volunteer(:'veteran', :'roleother');
select tests.create_volunteer(:'decliner', :'rolereviewer', 'declined');
select tests.create_volunteer(:'member', :'rolereviewer');
select tests.create_volunteer(:'paused', :'rolereviewer') as v_paused \gset
update public.volunteers set active = false where id = :'v_paused';

-- ---- Who may -------------------------------------------------------------------
select tests.authenticate_as(:'outsider');
select throws_ok(
	format('select public.add_to_role(%L, array[%L]::uuid[])', :'rolereviewer', :'newbie'),
	'Only those who approve this role may add someone to it',
	'someone who does not staff the role cannot add people to it'
);

-- ---- Refusals ------------------------------------------------------------------
select tests.authenticate_as(:'editor');
select throws_ok(
	format('select public.add_to_role(%L, array[]::uuid[])', :'rolereviewer'),
	'Nobody to add to this role',
	'an empty list is refused rather than reported as people added'
);
select throws_ok(
	format('select public.add_to_role(%L, array[%L]::uuid[])', :'rolereviewer', :'decliner'),
	'RR027',
	null,
	'someone who declined the role cannot be added to it'
);
select throws_ok(
	format('select public.add_to_role(%L, array[%L]::uuid[])', :'rolereviewer', :'member'),
	'RR004',
	null,
	'someone already in the role cannot be added again'
);
select throws_ok(
	format('select public.add_to_role(%L, array[%L]::uuid[])', :'rolereviewer', :'paused'),
	'RR004',
	null,
	'a volunteer who paused is not resumed by being added'
);
select throws_ok(
	format('select public.add_to_role(%L, array[%L, %L]::uuid[])', :'rolereviewer', :'newbie', :'decliner'),
	'RR027',
	null,
	'a refusal partway through the list fails the whole list'
);

select tests.clear_authentication();
select is(
	(select count(*)::integer from public.volunteers where scholarid = :'newbie'),
	0,
	'nobody earlier in a refused list was seated'
);
select is(
	(select accepted::text || '/' || active::text from public.volunteers where id = :'v_paused'),
	'accepted/false',
	'the paused volunteer is still paused'
);

-- ---- Seating -------------------------------------------------------------------
-- A non-admin top-role holder, with the invitee named twice: one id per distinct scholar.
select tests.authenticate_as(:'editor');
select is(
	(select cardinality(public.add_to_role(
		:'rolereviewer',
		array[:'invitee', :'veteran', :'newbie', :'invitee']::uuid[]))),
	3,
	'a top-role holder seats everyone named, once each'
);
select tests.clear_authentication();

select is(
	(select accepted::text || '/' || active::text from public.volunteers
		where scholarid = :'invitee' and roleid = :'rolereviewer'),
	'accepted/true',
	'an unanswered invitation becomes an acceptance'
);
select is(
	(select count(*)::integer from public.volunteers
		where scholarid = :'invitee' and roleid = :'rolereviewer'),
	1,
	'the invitation is reused, not duplicated'
);
select is(
	(select accepted::text || '/' || active::text from public.volunteers
		where scholarid = :'veteran' and roleid = :'rolereviewer'),
	'accepted/true',
	'an invitation is accepted for someone already serving elsewhere at the venue'
);
select is(
	(select accepted::text || '/' || active::text from public.volunteers
		where scholarid = :'newbie' and roleid = :'rolereviewer'),
	'accepted/true',
	'someone with no record is seated'
);

select is(
	(select count(*)::integer from public.transactions
		where from_venue = :'ven' and to_scholar = :'invitee' and status = 'approved'
			and purpose = 'Welcome tokens for joining a role'),
	1,
	'accepting a first invitation at the venue pays the welcome grant'
);
select is(
	(select count(*)::integer from public.transactions
		where from_venue = :'ven' and to_scholar = :'veteran'),
	0,
	'no welcome grant for someone who already had a role here'
);
select is(
	(select count(*)::integer from public.transactions
		where from_venue = :'ven' and to_scholar = :'newbie' and status = 'approved'),
	1,
	'someone seated fresh gets the welcome grant, as create_volunteer always gave'
);

select is(
	(select array_agg(scholar order by scholar)::text from public.emails
		where event = 'RoleEnrolled' and venue = :'ven' and sender = :'editor'),
	(select array_agg(s order by s)::text from unnest(array[:'invitee', :'veteran', :'newbie']::uuid[]) as s),
	'each person seated is emailed RoleEnrolled, once'
);

select * from finish();
rollback;
