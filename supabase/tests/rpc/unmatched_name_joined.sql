-- RPC tests for bringing imported people on board: the UnmatchedNameJoined notice and
-- public.add_to_role_and_match.
--
-- What is under test:
--   KEY      person_name_key agrees with nameTokens in matchPersonName.ts: case, accents,
--            punctuation and word order do not matter.
--   NOTICE   setting a name with the same words as an unmatched assignment emails whoever
--            could approve it, once per recipient per venue, never anyone conflicted on the
--            submission, and not again when the name changes to the same words.
--   STAFF    whoever staffs a role (can_staff_role) -- venue admins, holders of the top
--            role, and holders of the role's approving role -- may add people to it; anyone
--            else may not. Top-role holders see, match and hear about every unmatched name
--            at the venue.
--   SEAT     add_to_role_and_match seats the scholar and matches them in one step, turns an
--            invitation into an acceptance, and refuses someone who declined the role
--            (RR027).
--
-- The send_on_email_insert trigger is disabled for this rolled-back test, as in
-- new_volunteer_notice.sql: nothing here depends on mail actually being dispatched.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan (31);

alter table public.emails disable trigger send_on_email_insert;

-- ---- The key -------------------------------------------------------------------
select is(
	public.person_name_key('Petersen, Andrew'),
	public.person_name_key('andrew  PETERSEN'),
	'surname-first and given-name-first produce the same key'
);
select is(
	public.person_name_key('Muñoz'),
	public.person_name_key('Munoz'),
	'accents do not distinguish names'
);
select is(public.person_name_key('  , '), '', 'punctuation alone is no name');

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();

select tests.create_scholar('unj_minter@test.local')  as minter  \gset
select tests.create_scholar('unj_admin@test.local')   as admin   \gset
select tests.create_scholar('unj_admin2@test.local')  as admin2  \gset
select tests.create_scholar('unj_ae@test.local')      as ae      \gset
select tests.create_scholar('unj_jane@test.local')    as jane    \gset
select tests.create_scholar('unj_rev@test.local')     as rev     \gset
select tests.create_scholar('unj_decliner@test.local') as decliner \gset
select tests.create_scholar('unj_invitee@test.local') as invitee \gset
select tests.create_scholar('unj_eic@test.local')     as eic     \gset

select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'admin', :'admin2']::uuid[]) as ven \gset

select tests.create_role(:'ven', 0, null, false, false) as roleeditor \gset
select tests.create_role(:'ven', 1, null, false, true) as roleae \gset
select tests.create_role(:'ven', 2, :'roleae', false, false) as rolereviewer \gset
select tests.create_volunteer(:'ae', :'roleae') as v_ae \gset
select tests.create_volunteer(:'decliner', :'roleae', 'declined') as v_decliner \gset
select tests.create_volunteer(:'invitee', :'roleae', 'invited') as v_invitee \gset

select tests.create_submission_type(:'ven') as stype \gset

select tests.authenticate_as(:'admin');
select public.bulk_import_submissions(
	:'ven',
	jsonb_build_array(
		jsonb_build_object('externalid', 'U-1', 'submission_type', :'stype', 'title', 'One',
			'people', jsonb_build_array(
				jsonb_build_object('name', 'Jane Doe', 'person_role', :'roleae'),
				jsonb_build_object('name', 'Rev Unknown', 'person_role', :'rolereviewer'))),
		jsonb_build_object('externalid', 'U-2', 'submission_type', :'stype', 'title', 'Two',
			'people', jsonb_build_array(
				jsonb_build_object('name', 'Jane Doe', 'person_role', :'roleae'),
				jsonb_build_object('name', 'Rev Unknown', 'person_role', :'rolereviewer'))),
		jsonb_build_object('externalid', 'U-3', 'submission_type', :'stype', 'title', 'Three',
			'people', jsonb_build_array(
				jsonb_build_object('name', 'Dee Clined', 'person_role', :'roleae'),
				jsonb_build_object('name', 'Inna Vited', 'person_role', :'rolereviewer')))
	),
	'backlog'
);
select tests.clear_authentication();

select id as u1 from public.submissions where venue = :'ven' and externalid = 'U-1' \gset
select id as u2 from public.submissions where venue = :'ven' and externalid = 'U-2' \gset

-- The associate editor approves reviewers on U-2 only; the second admin is conflicted on U-1.
select tests.create_assignment(:'ven', :'u2', :'ae', :'roleae');
insert into public.conflicts (submissionid, scholarid) values (:'u1', :'admin2');

-- ---- The notice ----------------------------------------------------------------
update public.scholars set name = 'jane DOE' where id = :'jane';

select is(
	(select count(*)::integer from public.emails
		where event = 'UnmatchedNameJoined' and venue = :'ven' and scholar = :'admin'
			and args ->> 3 = :'jane'),
	1,
	'an admin gets one notice for a name on two submissions'
);
select ok(
	(select args ->> 4 from public.emails
		where event = 'UnmatchedNameJoined' and scholar = :'admin' and args ->> 3 = :'jane')
		like '%2 submissions%',
	'the notice counts the submissions under the name'
);
select is(
	(select args ->> 4 from public.emails
		where event = 'UnmatchedNameJoined' and scholar = :'admin2' and args ->> 3 = :'jane'),
	'Jane Doe as Test Role (1 submission)',
	'a conflicted admin hears only about the submissions they could approve'
);
select is(
	(select count(*)::integer from public.emails
		where event = 'UnmatchedNameJoined' and args ->> 3 = :'jane'
			and scholar not in (:'admin', :'admin2')),
	0,
	'nobody else hears about an AE name: the AE approves reviewers, not AEs'
);

update public.scholars set name = 'Rev Unknown' where id = :'rev';
select is(
	(select count(*)::integer from public.emails
		where event = 'UnmatchedNameJoined' and scholar = :'ae' and args ->> 3 = :'rev'),
	1,
	'the holder of the approving role on a submission hears about its reviewer'
);
select ok(
	(select args ->> 4 from public.emails
		where event = 'UnmatchedNameJoined' and scholar = :'ae' and args ->> 3 = :'rev')
		like '%(1 submission)',
	'the approver hears only about the submission they hold'
);

update public.scholars set name = 'Unknown, Rev' where id = :'rev';
select is(
	(select count(*)::integer from public.emails
		where event = 'UnmatchedNameJoined' and args ->> 3 = :'rev'),
	3,
	'reordering the same words sends nothing new'
);

update public.scholars set name = 'Nobody Imported' where id = :'decliner';
select is(
	(select count(*)::integer from public.emails
		where event = 'UnmatchedNameJoined' and args ->> 3 = :'decliner'),
	0,
	'a name matching nothing sends nothing'
);

-- ---- Finding them --------------------------------------------------------------
select tests.authenticate_as(:'admin');
select results_eq(
	format('select id from public.unmatched_name_scholars(%L, %L, %L)', :'ven', 'Doe, Jane', :'roleae'),
	format('values (%L::uuid)', :'jane'),
	'an admin finds the scholar whose name has the same words'
);
select tests.authenticate_as(:'ae');
select is_empty(
	format('select 1 from public.unmatched_name_scholars(%L, %L, %L)', :'ven', 'Jane Doe', :'roleae'),
	'someone who does not staff the role finds nobody'
);

-- ---- Seating and matching ------------------------------------------------------
select tests.authenticate_as(:'ae');
select throws_ok(
	format('select public.add_to_role_and_match(%L, %L, %L, %L)', :'ven', 'Jane Doe', :'roleae', :'jane'),
	'Only those who approve this role may add someone to it',
	'an associate editor cannot seat someone in a role they do not approve'
);

select tests.authenticate_as(:'admin');
select lives_ok(
	format('select public.add_to_role_and_match(%L, %L, %L, %L)', :'ven', 'Jane Doe', :'roleae', :'jane'),
	'an admin seats and matches someone who was not a volunteer'
);
select throws_ok(
	format('select public.add_to_role_and_match(%L, %L, %L, %L)', :'ven', 'Dee Clined', :'roleae', :'decliner'),
	'RR027',
	null,
	'someone who declined the role cannot be added to it'
);
select lives_ok(
	format('select public.add_to_role_and_match(%L, %L, %L, %L)', :'ven', 'Dee Clined', :'roleae', :'invitee'),
	'an unanswered invitation becomes an acceptance'
);

select tests.clear_authentication();
select is(
	(select accepted::text || '/' || active::text from public.volunteers
		where scholarid = :'jane' and roleid = :'roleae'),
	'accepted/true',
	'the new volunteer is accepted and active'
);
select is(
	(select count(*)::integer from public.assignments
		where scholar = :'jane' and role = :'roleae' and approved),
	1,
	'the import''s AE name is matched where nobody else holds the role'
);
select is(
	(select count(*)::integer from public.unmatched_assignments where venue = :'ven' and name = 'Jane Doe'),
	1,
	'the row skipped because the role is taken stays unmatched'
);
select is(
	(select accepted::text from public.volunteers where id = :'v_invitee'),
	'accepted',
	'the invitee is now accepted'
);
select is(
	(select count(*)::integer from public.emails
		where event = 'RoleEnrolled' and scholar in (:'jane', :'invitee') and venue = :'ven'),
	2,
	'both people seated are told'
);
select is(
	(select accepted::text from public.volunteers where id = :'v_decliner'),
	'declined',
	'a refused seat changes nothing'
);

-- ---- An editor-in-chief who is not an admin -------------------------------------
-- Seated only now, so the notices above were sent before there was a top-role holder.
select tests.create_volunteer(:'eic', :'roleeditor') as v_eic \gset

select tests.authenticate_as(:'eic');
select is(
	(select count(*)::integer from public.unmatched_assignments where venue = :'ven' and name = 'Rev Unknown'),
	2,
	'a top-role holder sees unmatched names on submissions they are not seated on'
);
select lives_ok(
	format('select public.add_to_role_and_match(%L, %L, %L, %L)', :'ven', 'Rev Unknown', :'rolereviewer', :'rev'),
	'a top-role holder who is not an admin adds and matches'
);
select tests.clear_authentication();
select is(
	(select count(*)::integer from public.assignments
		where scholar = :'rev' and role = :'rolereviewer' and approved),
	2,
	'the reviewer is matched on both submissions'
);

-- ---- Inviting follows the same rule ---------------------------------------------
select tests.authenticate_as(:'ae');
select lives_ok(
	format('select public.create_volunteer(%L, %L, false, false, null)', :'decliner', :'rolereviewer'),
	'the holder of a role''s approving role invites to it'
);
select throws_ok(
	format('select public.create_volunteer(%L, %L, false, false, null)', :'jane', :'roleae'),
	'You are not authorized to volunteer for this role',
	'but not to a role they do not approve'
);
select tests.authenticate_as(:'rev');
select throws_ok(
	format('select public.create_volunteer(%L, %L, false, false, null)', :'admin2', :'rolereviewer'),
	'You are not authorized to volunteer for this role',
	'a reviewer cannot put others in their own role'
);

-- ---- And hears about names --------------------------------------------------------
select tests.clear_authentication();
update public.scholars set name = 'Vited, Inna' where id = :'admin2';
select is(
	(select count(*)::integer from public.emails
		where event = 'UnmatchedNameJoined' and scholar = :'eic' and args ->> 3 = :'admin2'),
	1,
	'a top-role holder is emailed about any unmatched name at the venue'
);

select ok(
	not has_function_privilege('anon', 'public.add_to_role_and_match(uuid, text, uuid, uuid)', 'execute')
	and not has_function_privilege('authenticated', 'public._notify_unmatched_name_joined(uuid)', 'execute'),
	'anon cannot seat, and nobody but the owner can send the notice'
);

select * from finish();
rollback;
