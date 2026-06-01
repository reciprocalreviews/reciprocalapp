-- RLS tests for public.assignments.
--
-- Authorization model under test:
--   SELECT  the assigned scholar always sees their own assignment. Otherwise
--           only the approver CHAIN for the role (isInApproverChain, walks
--           roles.approver upward) or venue admins (isAdmin) may see it, and
--           NEVER if that viewer is conflicted on the submission (isConflicted).
--   INSERT  venue admins; OR an approver (isApprover) who is also assigned to the
--           submission (isAssigned); OR a bidder (bid=true) who is an active,
--           accepted volunteer on the assignment's role.
--   UPDATE  the assigned scholar or an approver (isApprover).
--   DELETE  the assigned scholar only.

\ir ../_helpers/helpers.sql.inc

begin;
create extension if not exists pgtap with schema extensions;
select plan(19);

-- ---- Fixtures (owner context) -------------------------------------------------
select tests.clear_authentication();

-- Scholars. admin/minter must be DISTINCT (no_minter_admins trigger).
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
-- placing them in rolechild's approver chain (isInApproverChain / isApprover).
select tests.create_volunteer(:'approver', :'roleapprover', 'accepted') as v_approver \gset
select tests.create_volunteer(:'conflicted', :'roleapprover', 'accepted') as v_conflicted \gset

-- The bidder is an active, accepted volunteer on rolechild itself.
select tests.create_volunteer(:'bidder', :'rolechild', 'accepted') as v_bidder \gset

select tests.create_submission_type(:'ven') as stype \gset
select tests.create_submission(:'ven', :'stype', array[:'outsider']::uuid[]) as sub \gset

-- The assignment under test: assignee assigned to rolechild on sub (approved).
select tests.create_assignment(:'ven', :'sub', :'assignee', :'rolechild', true, false) as asg \gset

-- The approver also holds an approved assignment on the submission (for the
-- roleapprover role), so isAssigned(sub) is true for the INSERT branch.
select tests.create_assignment(:'ven', :'sub', :'approver', :'roleapprover', true, false) as asg_approver \gset

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

-- A conflicted approver cannot see the assignment, despite being in the chain.
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
-- submission, so the isApprover+isAssigned branch does not apply to a non-bid
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

-- An approver (isApprover on the role) can update the assignment.
select tests.authenticate_as(:'approver');
select lives_ok(
	$$ update public.assignments set approved = true where id = $$ || quote_literal(:'asg'),
	'an approver can update the assignment'
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
