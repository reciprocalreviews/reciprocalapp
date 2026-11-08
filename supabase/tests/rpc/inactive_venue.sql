-- An inactive venue takes no new work (#42).
--
-- A venue is inactive while it is being configured and after it has closed. Either way, no
-- one may start new work there -- a submission, a self-signup, a resumed role, a bid, a call
-- for bids, reopened bidding -- and each attempt raises RR028. What stays open is what the
-- venue needs while it is inactive: its admins configure it and staff its roles, invitees
-- accept, approvers assign, and bidding can still be closed. Reactivating restores it all.
--
-- Inserting an email fires the send_on_email_insert AFTER trigger, which needs a vault URL the
-- RLS job does not set. Nothing here depends on mail being dispatched, so it is disabled for
-- this rolled-back test, as call_for_bids.sql does.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan (16);

alter table public.emails disable trigger send_on_email_insert;

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();

select tests.create_scholar('iv_minter@test.local')   as minter   \gset
select tests.create_scholar('iv_admin@test.local')    as admin    \gset
select tests.create_scholar('iv_author@test.local')   as author   \gset
select tests.create_scholar('iv_reviewer@test.local') as reviewer \gset
select tests.create_scholar('iv_stopped@test.local')  as stopped  \gset
select tests.create_scholar('iv_invitee@test.local')  as invitee  \gset
select tests.create_scholar('iv_stranger@test.local') as stranger \gset

select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as ven \gset

select tests.create_role(:'ven', 0) as toprole \gset
-- Open (not invite-only) and biddable, so the only thing refusing a signup or a bid below
-- is the venue's state.
select tests.create_role(:'ven', 1, null, true, false) as bidrole \gset

select tests.create_submission_type(:'ven') as stype \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as sub \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as closedsub \gset
update public.submissions set bidding_closed = true where id = :'closedsub';

select tests.create_volunteer(:'reviewer', :'bidrole') as v_reviewer \gset
select tests.create_volunteer(:'stopped', :'bidrole') as v_stopped \gset
update public.volunteers set active = false where id = :'v_stopped';

-- Close the venue.
update public.venues set inactive = 'Closed for the season.' where id = :'ven';

-- ---- Refused: new work ---------------------------------------------------------

select tests.authenticate_as(:'author');

select throws_ok (
	format(
		$$insert into public.submissions (venue, externalid, submission_type, authors, payments, transactions)
		values (%L, 'IV-1', %L, array[%L]::uuid[], array[0], array['00000000-0000-0000-0000-000000000000']::uuid[])$$,
		:'ven', :'stype', :'author'
	),
	'RR028', 'This venue is inactive',
	'a direct submission insert is refused'
);

select throws_ok (
	format(
		$$select public.create_submission(%L, 'IV-2', null, null, %L, array[%L]::uuid[], array[0], 'Title', '', '', 'Submission')$$,
		:'ven', :'stype', :'author'
	),
	'RR028', 'This venue is inactive',
	'create_submission is refused'
);

select tests.authenticate_as(:'stranger');

select throws_ok (
	format($$select public.create_volunteer(%L, %L, true, true, 0)$$, :'stranger', :'bidrole'),
	'RR028', 'This venue is inactive',
	'signing yourself up for a role is refused'
);

select tests.authenticate_as(:'stopped');

select throws_ok (
	format($$update public.volunteers set active = true where id = %L$$, :'v_stopped'),
	'RR028', 'This venue is inactive',
	'resuming a role you stopped is refused'
);

select tests.authenticate_as(:'reviewer');

select throws_ok (
	format(
		$$insert into public.assignments (venue, submission, scholar, role, bid, approved)
		values (%L, %L, %L, %L, true, false)$$,
		:'ven', :'sub', :'reviewer', :'bidrole'
	),
	'RR028', 'This venue is inactive',
	'a bid is refused'
);

select tests.authenticate_as(:'admin');

select throws_ok (
	format($$select public.queue_call_for_bids(%L, 'Please bid.')$$, :'bidrole'),
	'RR028', 'This venue is inactive',
	'a call for bids is refused, even from an admin'
);

select throws_ok (
	format($$select public.set_submission_open_for_bidding(%L, true)$$, :'closedsub'),
	'RR028', 'This venue is inactive',
	'reopening bidding is refused, even for an admin'
);

-- ---- Allowed: configuration, staffing, in-flight work ---------------------------

select lives_ok (
	format($$select public.set_submission_open_for_bidding(%L, false)$$, :'sub'),
	'an admin can still close bidding'
);

select lives_ok (
	format($$update public.roles set name = 'Referee' where id = %L$$, :'bidrole'),
	'an admin can still configure roles'
);

select lives_ok (
	format($$update public.venues set description = 'Back next year.' where id = %L$$, :'ven'),
	'an admin can still configure the venue'
);

select lives_ok (
	format($$select public.create_volunteer(%L, %L, false, false, 0)$$, :'invitee', :'bidrole'),
	'an admin can still invite someone to a role'
);

select lives_ok (
	format(
		$$insert into public.assignments (venue, submission, scholar, role, bid, approved)
		values (%L, %L, %L, %L, false, true)$$,
		:'ven', :'sub', :'reviewer', :'bidrole'
	),
	'an approver can still assign someone to a submission'
);

select tests.clear_authentication();
select id as v_invitee from public.volunteers
where scholarid = :'invitee' and roleid = :'bidrole' \gset

select tests.authenticate_as(:'invitee');

select lives_ok (
	format($$select public.accept_role_invite(%L, 'accepted')$$, :'v_invitee'),
	'an invitee can still accept'
);

select is (
	(select active from public.volunteers where id = :'v_invitee'),
	true,
	'accepting made the invitee active'
);

-- ---- Reactivated: back to normal -----------------------------------------------

select tests.clear_authentication();
-- Activating needs a web address (RR016), so give it one on the way.
update public.venues set inactive = null, slug = 'iv-test-venue' where id = :'ven';

select tests.authenticate_as(:'stranger');

select lives_ok (
	format($$select public.create_volunteer(%L, %L, true, true, 0)$$, :'stranger', :'bidrole'),
	'once active, signing up works again'
);

select tests.authenticate_as(:'stopped');

select lives_ok (
	format($$update public.volunteers set active = true where id = %L$$, :'v_stopped'),
	'once active, resuming works again'
);

select * from finish ();
rollback;
