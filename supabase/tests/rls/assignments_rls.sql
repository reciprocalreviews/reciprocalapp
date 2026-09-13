-- RLS tests for public.assignments.
--
-- Authorization model under test:
--   SELECT  the assigned scholar always sees their own assignment. Otherwise
--           only whoever may approve it ON THIS SUBMISSION (can_approve_assignment:
--           a venue admin, the submission's priority-0 editor, or the holder of the
--           approving role on it) may see it, and NEVER if that viewer is
--           conflicted on the submission (isConflicted).
--   INSERT  whoever may approve an assignment for this role on this submission
--           (can_approve_assignment, which covers venue admins); OR a bidder
--           (bid=true) who is an active, accepted volunteer on the assignment's
--           role; OR an editor claiming an unclaimed submission.
--   UPDATE  the assigned scholar, or whoever may approve it on this submission.
--
--   Volunteering in a role that approves another role is NOT enough on its own for
--   any of these: the approver must be seated on the submission in question.
--   DELETE  the assigned scholar only.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(23);

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();

-- Scholars. admin/minter kept DISTINCT, so nothing here turns on the overlap.
select tests.create_scholar('asg_minter@test.local') as minter \gset
select tests.create_scholar('asg_admin@test.local') as admin \gset
select tests.create_scholar('asg_assignee@test.local') as assignee \gset
select tests.create_scholar('asg_approver@test.local') as approver \gset
select tests.create_scholar('asg_conflicted@test.local') as conflicted \gset
select tests.create_scholar('asg_bidder@test.local') as bidder \gset
select tests.create_scholar('asg_outsider@test.local') as outsider \gset

select tests.create_currency(array[:'minter']::uuid[]) as cur \gset
select tests.create_venue(:'cur', array[:'admin']::uuid[]) as ven \gset

-- Role hierarchy: roleapprover is the approver of rolechild. Assignments under
-- test are made for rolechild, so the approver chain is anyone accepted on
-- roleapprover (and upward). rolechild is biddable so bidders can volunteer.
select tests.create_role(:'ven', 0, null, false, false) as roleapprover \gset
select tests.create_role(:'ven', 1, :'roleapprover', true, false) as rolechild \gset

-- The approver and the conflicted viewer are accepted volunteers on roleapprover,
-- placing them in rolechild's approver chain (isInApproverChain / isRoleApproverVolunteer).
select tests.create_volunteer(:'approver', :'roleapprover', 'accepted') as v_approver \gset
select tests.create_volunteer(:'conflicted', :'roleapprover', 'accepted') as v_conflicted \gset

-- The bidder is an active, accepted volunteer on rolechild itself.
select tests.create_volunteer(:'bidder', :'rolechild', 'accepted') as v_bidder \gset

-- An accepted volunteer on roleapprover who is seated on NOTHING. Volunteering in
-- the approving role used to be the whole test, venue-wide; now it buys nothing
-- until they hold the role on a particular submission.
select tests.create_scholar('asg_unseated@test.local') as unseated \gset
select tests.create_volunteer(:'unseated', :'roleapprover', 'accepted') as v_unseated \gset

-- Seated on the submission, but only in the CHILD role -- and also an accepted
-- volunteer on the approving role venue-wide. The old INSERT rule paired a
-- venue-wide approver check with isAssigned (an approved assignment in SOME role
-- on the submission), which this scholar satisfies, letting a plain reviewer seat
-- further reviewers alongside themselves.
select tests.create_scholar('asg_childseated@test.local') as child_seated \gset
select tests.create_volunteer(:'child_seated', :'roleapprover', 'accepted') as v_childseated \gset

select tests.create_submission_type(:'ven') as stype \gset
select tests.create_submission(:'ven', :'stype', array[:'outsider']::uuid[]) as sub \gset

-- The assignment under test: assignee assigned to rolechild on sub (approved).
select tests.create_assignment(:'ven', :'sub', :'assignee', :'rolechild', true, false) as asg \gset

-- The approver also holds an approved assignment on the submission (for the
-- roleapprover role), so isAssigned(sub) is true for the INSERT branch.
select tests.create_assignment(:'ven', :'sub', :'approver', :'roleapprover', true, false) as asg_approver \gset

-- :child_seated holds the child role on the submission, and nothing above it.
select tests.create_assignment(:'ven', :'sub', :'child_seated', :'rolechild', true, false) as asg_childseated \gset

-- The conflicted viewer also holds the approving role ON the submission, so the
-- ONLY thing standing between them and the assignment is the conflict. Without
-- this they would be excluded for merely being unseated, and the conflict guard
-- below would pass without ever being exercised.
select tests.create_assignment(:'ven', :'sub', :'conflicted', :'roleapprover', true, false) as asg_conflicted \gset

-- The conflicted viewer has a declared conflict on the submission. No builder for
-- conflicts; insert directly in owner context (reason has a default).
insert into public.conflicts (submissionid, scholarid)
values (:'sub', :'conflicted');

-- ---- Policy shape -------------------------------------------------------------
select policies_are(
	'public', 'assignments',
	array[
		'assignees and approvers can see assignments',
		'assignees and approvers can update assignments',
		'assignees can delete assignments',
		'admins, approvers and volunteers can create assignments'
	]
);

-- ---- SELECT -------------------------------------------------------------------
-- The assigned scholar always sees their own assignment.
select tests.authenticate_as(:'assignee');
select isnt_empty(
	$$ select 1 from public.assignments where id = $$ || quote_literal(:'asg'),
	'the assigned scholar can see their own assignment'
);

-- A scholar up the approver chain can see the assignment.
select tests.authenticate_as(:'approver');
select isnt_empty(
	$$ select 1 from public.assignments where id = $$ || quote_literal(:'asg'),
	'an approver up the chain can see the assignment'
);

-- A venue admin can see the assignment.
select tests.authenticate_as(:'admin');
select isnt_empty(
	$$ select 1 from public.assignments where id = $$ || quote_literal(:'asg'),
	'a venue admin can see the assignment'
);

-- An unrelated authenticated scholar cannot see the assignment.
select tests.authenticate_as(:'outsider');
select is_empty(
	$$ select 1 from public.assignments where id = $$ || quote_literal(:'asg'),
	'an unrelated scholar cannot see the assignment'
);

-- Volunteering in the approving role, with no assignment on this submission, is
-- not enough to see an assignment on it.
select tests.authenticate_as(:'unseated');
select is_empty(
	$$ select 1 from public.assignments where id = $$ || quote_literal(:'asg'),
	'an approver not seated on the submission cannot see its assignments'
);

-- A conflicted approver cannot see the assignment, despite approving it here.
select tests.authenticate_as(:'conflicted');
select is_empty(
	$$ select 1 from public.assignments where id = $$ || quote_literal(:'asg'),
	'a conflicted approver cannot see the assignment'
);

-- Anonymous visitors cannot see assignments (policy is to authenticated only).
select tests.authenticate_as_anon();
select is_empty(
	$$ select 1 from public.assignments where id = $$ || quote_literal(:'asg'),
	'anonymous visitors cannot see assignments'
);

-- ---- Open review (venue non-anonymous) ----------------------------------------
-- The submission's author is :outsider. With the default anonymous venue they
-- cannot see the assignment (covered above). In open review they can.
select tests.clear_authentication();
update public.venues set anonymous_assignments = false where id = :'ven';
select tests.authenticate_as(:'outsider');
select isnt_empty(
	$$ select 1 from public.assignments where id = $$ || quote_literal(:'asg'),
	'in open review (non-anonymous), the submission author can see assignments'
);
select tests.clear_authentication();
update public.venues set anonymous_assignments = true where id = :'ven';

-- ---- INSERT -------------------------------------------------------------------
-- A venue admin can create any assignment.
select tests.authenticate_as(:'admin');
select lives_ok(
	$$ insert into public.assignments (venue, submission, scholar, role)
	   values ( $$ || quote_literal(:'ven') || $$, $$ || quote_literal(:'sub') || $$,
	            $$ || quote_literal(:'outsider') || $$, $$ || quote_literal(:'rolechild') || $$ ) $$,
	'a venue admin can create an assignment'
);

-- An approver assigned to the submission can create an assignment for the role.
select tests.authenticate_as(:'approver');
select lives_ok(
	$$ insert into public.assignments (venue, submission, scholar, role)
	   values ( $$ || quote_literal(:'ven') || $$, $$ || quote_literal(:'sub') || $$,
	            $$ || quote_literal(:'bidder') || $$, $$ || quote_literal(:'rolechild') || $$ ) $$,
	'an approver assigned to the submission can create an assignment'
);

-- The approver seated on the submission may also seat THEMSELVES in a role they
-- approve -- nothing in the branch constrains who is being seated.
select tests.authenticate_as(:'approver');
select lives_ok(
	$$ insert into public.assignments (venue, submission, scholar, role)
	   values ( $$ || quote_literal(:'ven') || $$, $$ || quote_literal(:'sub') || $$,
	            $$ || quote_literal(:'approver') || $$, $$ || quote_literal(:'rolechild') || $$ ) $$,
	'an approver seated on the submission can seat themselves in a role they approve'
);

-- Seated on the submission only in the child role, plus a venue-wide volunteer
-- commitment to the approving role. That combination used to satisfy
-- isRoleApproverVolunteer + isAssigned; it may not seat anyone.
select tests.authenticate_as(:'child_seated');
select throws_ok(
	$$ insert into public.assignments (venue, submission, scholar, role)
	   values ( $$ || quote_literal(:'ven') || $$, $$ || quote_literal(:'sub') || $$,
	            $$ || quote_literal(:'outsider') || $$, $$ || quote_literal(:'rolechild') || $$ ) $$,
	'42501',
	null,
	'holding the child role on a submission does not let a venue-wide approver seat others there'
);

-- An active accepted volunteer on the role can create their own bid (bid=true).
select tests.authenticate_as(:'bidder');
select lives_ok(
	$$ insert into public.assignments (venue, submission, scholar, role, bid)
	   values ( $$ || quote_literal(:'ven') || $$, $$ || quote_literal(:'sub') || $$,
	            $$ || quote_literal(:'bidder') || $$, $$ || quote_literal(:'rolechild') || $$, true ) $$,
	'an active accepted volunteer can create a bid on the role'
);

-- An unrelated scholar cannot create an assignment (no branch applies).
select tests.authenticate_as(:'outsider');
select throws_ok(
	$$ insert into public.assignments (venue, submission, scholar, role)
	   values ( $$ || quote_literal(:'ven') || $$, $$ || quote_literal(:'sub') || $$,
	            $$ || quote_literal(:'outsider') || $$, $$ || quote_literal(:'rolechild') || $$ ) $$,
	'42501',
	null,
	'an unrelated scholar cannot create an assignment'
);

-- The bidder is an approver-chain member of nothing and is NOT assigned to the
-- submission, so the isRoleApproverVolunteer+isAssigned branch does not apply to a non-bid
-- insert: a non-bid insert by the bidder is denied.
select tests.authenticate_as(:'bidder');
select throws_ok(
	$$ insert into public.assignments (venue, submission, scholar, role, bid)
	   values ( $$ || quote_literal(:'ven') || $$, $$ || quote_literal(:'sub') || $$,
	            $$ || quote_literal(:'bidder') || $$, $$ || quote_literal(:'rolechild') || $$, false ) $$,
	'42501',
	null,
	'a volunteer cannot create a non-bid assignment for themselves'
);

-- ---- UPDATE -------------------------------------------------------------------
-- The assigned scholar can update their own assignment.
select tests.authenticate_as(:'assignee');
select lives_ok(
	$$ update public.assignments set completed = true where id = $$ || quote_literal(:'asg'),
	'the assigned scholar can update their own assignment'
);

-- An approver (isRoleApproverVolunteer on the role) can update the assignment.
select tests.authenticate_as(:'approver');
select lives_ok(
	$$ update public.assignments set approved = true where id = $$ || quote_literal(:'asg'),
	'an approver can update the assignment'
);

-- An approver not seated on this submission cannot update its assignments. Like
-- the unrelated case below, the using clause filters the row rather than erroring.
select tests.authenticate_as(:'unseated');
update public.assignments set completed = false where id = :'asg';
select tests.clear_authentication();
select is(
	(select completed from public.assignments where id = :'asg'),
	true,
	'an approver not seated on the submission cannot update its assignments (no-op)'
);

-- An unrelated scholar's UPDATE is filtered by the using clause (0 rows, no error).
select tests.authenticate_as(:'outsider');
update public.assignments set completed = false where id = :'asg';
select tests.clear_authentication();
select is(
	(select completed from public.assignments where id = :'asg'),
	true,
	'an unrelated scholar cannot update the assignment (no-op)'
);

-- ---- DELETE -------------------------------------------------------------------
-- An approver cannot delete (delete using = assignee only → 0 rows, no error).
select tests.authenticate_as(:'approver');
delete from public.assignments where id = :'asg';
select tests.clear_authentication();
select is(
	(select count(*)::int from public.assignments where id = :'asg'),
	1,
	'an approver cannot delete the assignment'
);

-- An unrelated scholar cannot delete the assignment (0 rows, no error).
select tests.authenticate_as(:'outsider');
delete from public.assignments where id = :'asg';
select tests.clear_authentication();
select is(
	(select count(*)::int from public.assignments where id = :'asg'),
	1,
	'an unrelated scholar cannot delete the assignment'
);

-- The assigned scholar can delete their own assignment.
select tests.authenticate_as(:'assignee');
select lives_ok(
	$$ delete from public.assignments where id = $$ || quote_literal(:'asg'),
	'the assigned scholar can delete their own assignment'
);

select * from finish();
rollback;
