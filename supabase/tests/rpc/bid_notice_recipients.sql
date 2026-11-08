-- Tests for public.bid_notice_recipients: who is told a bid arrived.
--
-- Rule under test: whoever holds the bid-on role's approving role on this submission,
-- after dropping the bidder and anyone conflicted on the submission -- and no one else,
-- not even when that leaves no one. Nothing at all unless the caller has bid for this
-- role on this submission.
--
-- The regressions this guards: every bid used to mail every venue admin and every
-- priority-0 volunteer, whichever submission and role it was for; and after that, a
-- submission with no approver seated fell back to its editor and then the admins, which
-- mailed an editor seated on every submission about every bid on it.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();

select tests.create_scholar('bnr_minter@test.local') as minter \gset
select tests.create_scholar('bnr_admin@test.local') as admin \gset
select tests.create_scholar('bnr_editor@test.local') as editor \gset
select tests.create_scholar('bnr_idle_editor@test.local') as idle_editor \gset
select tests.create_scholar('bnr_lead@test.local') as lead \gset
select tests.create_scholar('bnr_bidder@test.local') as bidder \gset
select tests.create_scholar('bnr_outsider@test.local') as outsider \gset
select tests.create_scholar('bnr_author@test.local') as author \gset

select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as ven \gset

-- Editor (priority 0) approves Lead; Lead approves Reviewer, which is biddable.
select tests.create_role(:'ven', 0, null, false, false) as editor_role \gset
select tests.create_role(:'ven', 1, :'editor_role', false, false) as lead_role \gset
select tests.create_role(:'ven', 2, :'lead_role', true, false) as review_role \gset
-- A biddable role with no approver configured.
select tests.create_role(:'ven', 3, null, true, false) as open_role \gset

-- An editor-role volunteer seated on nothing: the old fan-out mailed them every bid.
select tests.create_volunteer(:'editor', :'editor_role', 'accepted') as v_editor \gset
select tests.create_volunteer(:'idle_editor', :'editor_role', 'accepted') as v_idle \gset
select tests.create_volunteer(:'lead', :'lead_role', 'accepted') as v_lead \gset
select tests.create_volunteer(:'bidder', :'review_role', 'accepted') as v_bidder \gset
select tests.create_volunteer(:'bidder', :'lead_role', 'accepted') as v_bidder_lead \gset
select tests.create_volunteer(:'bidder', :'open_role', 'accepted') as v_bidder_open \gset

select tests.create_submission_type(:'ven') as stype \gset

-- sub_full: an editor and a lead are seated.
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as sub_full \gset
select tests.create_assignment(:'ven', :'sub_full', :'editor', :'editor_role', true, false) as a1 \gset
select tests.create_assignment(:'ven', :'sub_full', :'lead', :'lead_role', true, false) as a2 \gset
select tests.create_assignment(:'ven', :'sub_full', :'bidder', :'review_role', false, true) as b1 \gset
select tests.create_assignment(:'ven', :'sub_full', :'bidder', :'open_role', false, true) as b6 \gset

-- sub_editor: only an editor is seated.
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as sub_editor \gset
select tests.create_assignment(:'ven', :'sub_editor', :'editor', :'editor_role', true, false) as a3 \gset
select tests.create_assignment(:'ven', :'sub_editor', :'bidder', :'review_role', false, true) as b2 \gset

-- sub_empty: nobody is seated.
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as sub_empty \gset
select tests.create_assignment(:'ven', :'sub_empty', :'bidder', :'review_role', false, true) as b3 \gset

-- sub_conflict: the seated lead is conflicted, and the editor is not told in their place.
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as sub_conflict \gset
select tests.create_assignment(:'ven', :'sub_conflict', :'editor', :'editor_role', true, false) as a4 \gset
select tests.create_assignment(:'ven', :'sub_conflict', :'lead', :'lead_role', true, false) as a5 \gset
select tests.create_assignment(:'ven', :'sub_conflict', :'bidder', :'review_role', false, true) as b4 \gset
insert into public.conflicts (submissionid, scholarid) values (:'sub_conflict', :'lead');

-- sub_self: the bidder is the seated lead, so they are skipped, and no one is told.
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as sub_self \gset
select tests.create_assignment(:'ven', :'sub_self', :'editor', :'editor_role', true, false) as a6 \gset
select tests.create_assignment(:'ven', :'sub_self', :'bidder', :'lead_role', true, false) as a7 \gset
select tests.create_assignment(:'ven', :'sub_self', :'bidder', :'review_role', false, true) as b5 \gset

-- ---- As the bidder -------------------------------------------------------------
select tests.authenticate_as(:'bidder');

select is(
	(select array_agg(r) from public.bid_notice_recipients(:'sub_full', :'review_role') r),
	array[:'lead']::uuid[],
	'the approving role''s holder on the submission is told, and no editor or admin'
);

select is(
	(select count(*)::int from public.bid_notice_recipients(:'sub_editor', :'review_role') r),
	0,
	'with no approving-role holder seated, the submission''s editor is not told in their place'
);

select is(
	(select count(*)::int from public.bid_notice_recipients(:'sub_empty', :'review_role') r),
	0,
	'with nobody seated, the venue admins are not told either'
);

select is(
	(select count(*)::int from public.bid_notice_recipients(:'sub_conflict', :'review_role') r),
	0,
	'a conflicted approver is skipped, and no one is told in their place'
);

select is(
	(select count(*)::int from public.bid_notice_recipients(:'sub_self', :'review_role') r),
	0,
	'the bidder is never told about their own bid'
);

select is(
	(select count(*)::int from public.bid_notice_recipients(:'sub_full', :'open_role') r),
	0,
	'a role with no approver configured tells no one, even with an editor seated'
);

select is(
	(select count(*)::int from public.bid_notice_recipients(:'sub_full', :'lead_role') r),
	0,
	'nothing for a role the caller did not bid for'
);

-- ---- As someone who did not bid ------------------------------------------------
select tests.authenticate_as(:'outsider');

select is(
	(select count(*)::int from public.bid_notice_recipients(:'sub_full', :'review_role') r),
	0,
	'a caller with no bid on the submission learns nothing'
);

select tests.clear_authentication();

select ok(
	not has_function_privilege('anon', 'public.bid_notice_recipients(uuid,uuid)', 'execute'),
	'anon cannot call it'
);

select * from finish();
rollback;
