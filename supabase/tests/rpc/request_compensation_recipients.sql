-- Tests for who public.request_compensation says to tell, and what it says about the request.
--
-- Rule under test: whoever holds the role's approving role on the submission; failing that,
-- its priority-0 editors; failing that, the venue's admins. Each tier drops the requester
-- and anyone conflicted on the submission before asking whether it is empty.
--
-- The regression this guards: every request went to the whole approver union, so a venue
-- admin who was also the submission's editor heard about each request an associate editor
-- was responsible for answering.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(10);

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();

select tests.create_scholar('rcr_minter@test.local') as minter \gset
select tests.create_scholar('rcr_admin@test.local') as admin \gset
select tests.create_scholar('rcr_editor@test.local') as editor \gset
select tests.create_scholar('rcr_lead@test.local') as lead \gset
select tests.create_scholar('rcr_reviewer@test.local') as reviewer \gset
select tests.create_scholar('rcr_author@test.local') as author \gset
update public.scholars set name = 'Ada Reviewer' where id = :'reviewer';

select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as ven \gset

-- Editor (priority 0) approves Lead; Lead approves Reviewer. Open has no approver.
select tests.create_role(:'ven', 0, null, false, false) as editor_role \gset
select tests.create_role(:'ven', 1, :'editor_role', false, false) as lead_role \gset
select tests.create_role(:'ven', 2, :'lead_role', false, false) as review_role \gset
select tests.create_role(:'ven', 3, null, false, false) as open_role \gset
update public.roles set name = 'Reviewer' where id = :'review_role';

select tests.create_volunteer(:'reviewer', :'review_role', 'accepted') as v_reviewer \gset
select tests.create_volunteer(:'reviewer', :'open_role', 'accepted') as v_open \gset

select tests.create_submission_type(:'ven') as stype \gset

-- sub_full: an editor and a lead are seated; the reviewer is assigned.
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as sub_full \gset
update public.submissions set title = 'On Compilers' where id = :'sub_full';
select tests.create_assignment(:'ven', :'sub_full', :'editor', :'editor_role') as a1 \gset
select tests.create_assignment(:'ven', :'sub_full', :'lead', :'lead_role') as a2 \gset
select tests.create_assignment(:'ven', :'sub_full', :'reviewer', :'review_role') as a3 \gset
select tests.create_assignment(:'ven', :'sub_full', :'reviewer', :'open_role') as a4 \gset

-- sub_editor: only an editor is seated.
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as sub_editor \gset
select tests.create_assignment(:'ven', :'sub_editor', :'editor', :'editor_role') as a5 \gset
select tests.create_assignment(:'ven', :'sub_editor', :'reviewer', :'review_role') as a6 \gset

-- sub_empty: nobody is seated, and the reviewer files a claim.
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as sub_empty \gset

-- sub_conflict: the seated lead is conflicted, so the editor is told in their place.
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as sub_conflict \gset
select tests.create_assignment(:'ven', :'sub_conflict', :'editor', :'editor_role') as a7 \gset
select tests.create_assignment(:'ven', :'sub_conflict', :'lead', :'lead_role') as a8 \gset
select tests.create_assignment(:'ven', :'sub_conflict', :'reviewer', :'review_role') as a9 \gset
insert into public.conflicts (submissionid, scholarid) values (:'sub_conflict', :'lead');

-- sub_admin_editor: the admin is also the seated editor, and no lead is seated yet.
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as sub_admin_editor \gset
select tests.create_assignment(:'ven', :'sub_admin_editor', :'admin', :'editor_role') as a10 \gset
select tests.create_assignment(:'ven', :'sub_admin_editor', :'lead', :'lead_role', false) as a11 \gset
select tests.create_assignment(:'ven', :'sub_admin_editor', :'reviewer', :'review_role') as a12 \gset

-- ---- As the reviewer -----------------------------------------------------------
select tests.authenticate_as(:'reviewer');

select public.request_compensation(:'ven', :'sub_full'::text, :'review_role') as full_result \gset

select is(
	:'full_result'::jsonb -> 'recipients',
	jsonb_build_array(:'lead'),
	'the approving role''s holder is told, and neither the editor nor the admin'
);

select is(
	jsonb_build_array(
		:'full_result'::jsonb ->> 'title',
		:'full_result'::jsonb ->> 'role',
		:'full_result'::jsonb ->> 'requester'
	),
	jsonb_build_array('On Compilers', 'Reviewer', 'Ada Reviewer'),
	'the result names the submission, the role and the requester, for the email'
);

select is(
	public.request_compensation(:'ven', :'sub_editor'::text, :'review_role') -> 'recipients',
	jsonb_build_array(:'editor'),
	'with no approver seated, the submission''s editor is told, and not the admin'
);

select is(
	public.request_compensation(:'ven', :'sub_empty'::text, :'review_role') -> 'recipients',
	jsonb_build_array(:'admin'),
	'with nobody seated, a claim reaches the venue''s admins'
);

select is(
	public.request_compensation(:'ven', :'sub_conflict'::text, :'review_role') -> 'recipients',
	jsonb_build_array(:'editor'),
	'a conflicted approver hands the request on to the editor'
);

select is(
	public.request_compensation(:'ven', :'sub_admin_editor'::text, :'review_role') -> 'recipients',
	jsonb_build_array(:'admin'),
	'an unapproved lead is not seated, so the editor -- here also the admin -- is told once'
);

select is(
	public.request_compensation(:'ven', :'sub_full'::text, :'open_role') -> 'recipients',
	jsonb_build_array(:'editor'),
	'a role with no approver configured goes to the submission''s editor'
);

-- ---- The requester is never told -----------------------------------------------
select tests.clear_authentication();
select tests.create_volunteer(:'lead', :'review_role', 'accepted') as v_lead_review \gset
select tests.create_assignment(:'ven', :'sub_editor', :'lead', :'review_role') as a13 \gset
select tests.create_assignment(:'ven', :'sub_editor', :'lead', :'lead_role') as a14 \gset

select tests.authenticate_as(:'lead');
select is(
	public.request_compensation(:'ven', :'sub_editor'::text, :'review_role') -> 'recipients',
	jsonb_build_array(:'editor'),
	'a requester seated as their own approver is skipped, and the editor is told'
);

select is(
	public.request_compensation(:'ven', :'sub_editor'::text, :'review_role') ->> 'requester',
	'Test Scholar',
	'the requester is named as their profile names them'
);

select tests.clear_authentication();

select ok(
	not has_function_privilege('anon', 'public.request_compensation(uuid,text,uuid)', 'execute'),
	'anon cannot call it'
);

select * from finish();
rollback;
