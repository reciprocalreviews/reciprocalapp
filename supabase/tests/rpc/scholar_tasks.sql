-- Tests for public.scholar_tasks and public.scholar_approver_roles, the two functions
-- behind the Tasks table on a scholar's profile. Defined in migration
-- 20260920000000_editor_tasks_when_actionable.sql.
--
-- The bug they replace: a venue with a sole editor seats that editor on EVERY submission
-- it receives (create_submission, bulk_import_submissions), and the seat stays approved
-- and uncompleted until mark_submission_done pays it. The page asked for "all my open
-- assignments" and labelled every row "Review", so a venue's editor opened their profile
-- to find every paper the venue had ever received listed as a review they owed.
--
-- So the cases below are mostly about what must NOT appear. A priority-0 assignment is a
-- standing seat rather than a piece of work, and it earns a row only when the submission
-- is genuinely waiting on the editor.
--
-- Two of these are load-bearing beyond the feature:
--
--   * The conflicted-editor case. scholar_tasks is SECURITY DEFINER because deciding
--     whether a submission is waiting on its editor means aggregating over SIBLING
--     assignment rows, and the assignments SELECT policy admits those to an editor only
--     `and not public.isConflicted(submission)`. Run as the caller, a conflicted editor
--     would see no siblings and every submission would report 'unstaffed' -- the
--     dangerous direction, because it is the one that ADDS rows. That test fails if
--     anyone ever "simplifies" the function to SECURITY INVOKER.
--
--   * The approver-roles case. The profile load used to derive the approver's roles from
--     the very array it rendered as tasks, so narrowing the task list silently deleted
--     the approver's "pending assignment" and "compensation to approve" rows. The two are
--     separate functions now, and the test below pins the separation: an assignment that
--     has dropped off the task list must still confer its approver roles.
--
-- Grants are not checked here. scholar_tasks is SECURITY DEFINER and not on the
-- allowlist, so supabase/tests/rls/definer_grants.sql check 1 fails if its
-- `revoke execute ... from anon` is ever dropped or undone by a later re-creation.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(22);

-- ---- Fixtures (owner context) ------------------------------------------------
select tests.clear_authentication();
select tests.create_scholar('st_minter@test.local') as minter \gset
select tests.create_scholar('st_admin@test.local') as admin \gset
select tests.create_scholar('st_editor@test.local') as editor \gset
select tests.create_scholar('st_reviewer@test.local') as reviewer \gset
select tests.create_scholar('st_other@test.local') as other \gset
select tests.create_scholar('st_author@test.local') as author \gset

select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as ven \gset

-- An editor role and a reviewer role the editor approves on. Distinct names, because one
-- of the things under test is that the Kind cell now reads the venue's own role name
-- rather than a fixed "Review".
select tests.create_role(:'ven', 0) as editor_role \gset
update public.roles set name = 'Editor' where id = :'editor_role';
select tests.create_role(:'ven', 2, :'editor_role') as reviewer_role \gset
update public.roles set name = 'Reviewer' where id = :'reviewer_role';

select tests.create_volunteer(:'editor', :'editor_role') as v_ed \gset
select tests.create_volunteer(:'reviewer', :'reviewer_role') as v_rev \gset
select tests.create_submission_type(:'ven', 0) as stype \gset

-- Five submissions, one per situation the editor can be in, plus one for the reviewer.
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s_unstaffed \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s_working \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s_requested \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s_ready \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s_bidonly \gset
select tests.create_submission(:'ven', :'stype', array[:'author']::uuid[]) as s_conflict \gset

-- The editor is seated on all six, exactly as create_submission would seat them.
select tests.create_assignment(:'ven', :'s_unstaffed', :'editor', :'editor_role') as a_ed1 \gset
select tests.create_assignment(:'ven', :'s_working',   :'editor', :'editor_role') as a_ed2 \gset
select tests.create_assignment(:'ven', :'s_requested', :'editor', :'editor_role') as a_ed3 \gset
select tests.create_assignment(:'ven', :'s_ready',     :'editor', :'editor_role') as a_ed4 \gset
select tests.create_assignment(:'ven', :'s_bidonly',   :'editor', :'editor_role') as a_ed5 \gset
select tests.create_assignment(:'ven', :'s_conflict',  :'editor', :'editor_role') as a_ed6 \gset

-- s_unstaffed: nobody else seated at all.
-- s_working: a reviewer is seated and working.
select tests.create_assignment(:'ven', :'s_working', :'reviewer', :'reviewer_role') as a_rev_working \gset
-- s_requested: the reviewer has finished and asked to be paid, but has not been paid.
select tests.create_assignment(:'ven', :'s_requested', :'reviewer', :'reviewer_role') as a_rev_req \gset
update public.assignments set compensation_requested_at = now() where id = :'a_rev_req';
-- s_ready: the reviewer has been compensated, so the submission can be marked done.
select tests.create_assignment(:'ven', :'s_ready', :'reviewer', :'reviewer_role', true, false, true) as a_rev_done \gset
-- s_bidonly: an unapproved bid, which is not a seat.
select tests.create_assignment(:'ven', :'s_bidonly', :'reviewer', :'reviewer_role', false, true) as a_rev_bid \gset
-- s_conflict: a reviewer is working, AND the editor has declared a conflict.
select tests.create_assignment(:'ven', :'s_conflict', :'reviewer', :'reviewer_role') as a_rev_conf \gset
insert into public.conflicts (submissionid, scholarid, reason) values (:'s_conflict', :'editor', 'test');

--------------------------------------------------------------------------------
-- The editor's view.
--------------------------------------------------------------------------------
select tests.authenticate_as(:'editor');

-- 1-2. Nobody seated yet: the editor has to recruit, so this IS their task.
select is(
	(select count(*)::int from public.scholar_tasks() where submission = :'s_unstaffed'),
	1,
	'an editor sees a submission nobody is seated on'
);
select is(
	(select state from public.scholar_tasks() where submission = :'s_unstaffed'),
	'unstaffed',
	'... reported as unstaffed'
);

-- 3. THE CENTRAL REGRESSION. A reviewer is seated and working: the submission is waiting
-- on the reviewer, not on the editor, and must not be on the editor's list at all.
select is_empty(
	format($$select 1 from public.scholar_tasks() where submission = %L$$, :'s_working'),
	'an editor does NOT see a submission whose reviewer is still working'
);

-- 4. A compensation request is not completion -- mark_submission_done still blocks on
-- this assignment -- so the editor cannot act yet and the row stays off their list.
select is_empty(
	format($$select 1 from public.scholar_tasks() where submission = %L$$, :'s_requested'),
	'an editor does NOT see a submission whose reviewer has only requested compensation'
);

-- 5-6. Every seated reviewer settled: the editor can close it.
select is(
	(select state from public.scholar_tasks() where submission = :'s_ready'),
	'ready',
	'an editor sees a submission whose reviewers are all settled, as ready'
);
select is(
	(select role_name from public.scholar_tasks() where submission = :'s_ready'),
	'Editor',
	'... labelled with the venue role name, not a fixed "Review"'
);

-- 7. A bid is not a seat: review cannot start until the editor approves someone.
select is(
	(select state from public.scholar_tasks() where submission = :'s_bidonly'),
	'unstaffed',
	'an unapproved bid does not staff a submission'
);

-- 8. SECURITY DEFINER, pinned. Conflicted, the editor cannot select the sibling
-- assignment rows -- so run as the caller this would report 'unstaffed' and put the row
-- back on the list. It must behave exactly as the unconflicted case does.
select is_empty(
	format($$select 1 from public.scholar_tasks() where submission = %L$$, :'s_conflict'),
	'a CONFLICTED editor still does not see a submission whose reviewer is working'
);

-- 9. Nothing else leaked in.
select is(
	(select count(*)::int from public.scholar_tasks()),
	3,
	'the editor sees exactly the three submissions waiting on them'
);
select is(
	(select count(distinct priority)::int from public.scholar_tasks()),
	1,
	'... all of them their own priority-0 seat'
);

-- 10. The editor approves on the reviewer role, and still does even though four of their
-- six assignments have dropped off the task list.
select is(
	(select count(*)::int from public.scholar_approver_roles()),
	1,
	'the editor approves on exactly one role'
);
select is(
	(select role from public.scholar_approver_roles()),
	:'reviewer_role'::uuid,
	'... the reviewer role'
);

--------------------------------------------------------------------------------
-- The reviewer's view.
--------------------------------------------------------------------------------
select tests.clear_authentication();
select tests.authenticate_as(:'reviewer');

-- 11-13. Ordinary work in progress is a task, named by its role.
select is(
	(select state from public.scholar_tasks() where submission = :'s_working'),
	'assigned',
	'a reviewer sees work in progress'
);
select is(
	(select role_name from public.scholar_tasks() where submission = :'s_working'),
	'Reviewer',
	'... named by their role'
);
select is(
	(select priority from public.scholar_tasks() where submission = :'s_working'),
	2,
	'... carrying the role priority'
);

-- 14. Work they have finished and asked to be paid for is awaiting an APPROVER, not
-- them. It appears on the approver's list instead.
select is_empty(
	format($$select 1 from public.scholar_tasks() where submission = %L$$, :'s_requested'),
	'a reviewer who has requested compensation no longer owes the work'
);

-- 15. Compensated work is gone too.
select is_empty(
	format($$select 1 from public.scholar_tasks() where submission = %L$$, :'s_ready'),
	'a compensated assignment is not a task'
);

-- 16. An unapproved bid is not work yet.
select is_empty(
	format($$select 1 from public.scholar_tasks() where submission = %L$$, :'s_bidonly'),
	'an unapproved bid is not a task'
);

-- 17. The reviewer approves on nothing.
select is_empty(
	$$select 1 from public.scholar_approver_roles()$$,
	'a reviewer with no approving role gets no approver roles'
);

--------------------------------------------------------------------------------
-- Isolation: the function answers for auth.uid() and nobody else.
--------------------------------------------------------------------------------
select tests.clear_authentication();
select tests.authenticate_as(:'other');

select is_empty(
	$$select 1 from public.scholar_tasks()$$,
	'a scholar with no assignments sees no tasks'
);
select is_empty(
	$$select 1 from public.scholar_approver_roles()$$,
	'... and no approver roles'
);

-- 18. Anonymous callers get nothing, even before the grant check in definer_grants.sql.
select tests.clear_authentication();
select tests.authenticate_as_anon();
select throws_ok(
	$$select 1 from public.scholar_tasks()$$,
	'42501',
	null,
	'scholar_tasks is not callable without a session'
);

select * from finish();
rollback;
