-- "Approver" means approver OF A SUBMISSION, not of a role.
--
-- Two rules with the same name had drifted apart. The RLS policies asked a
-- venue-wide question -- "do I volunteer in a role that approves role X,
-- anywhere in this venue?" (isRoleApproverVolunteer, isInApproverChain) --
-- while every UI action asked a submission-scoped one, can_approve_assignment:
-- "do I hold an approved assignment ON THIS SUBMISSION in the approving role,
-- or am I its editor?"
--
-- At a venue whose Reviewer role is approved by an Associate Editor role, the
-- venue-wide question is unconditionally true for every accepted AE volunteer,
-- on every submission. The reported symptom: an AE with no assignments at all
-- saw a submission listed as visible to them, showing two reviewers they had no
-- relationship to, at a venue with anonymous_assignments on. The same mismatch
-- also let any such volunteer approve, unassign, and seat assignments on
-- submissions they hold no role on -- writes the UI never offered, but the
-- database allowed.
--
-- This makes can_approve_assignment the single definition across reading,
-- seating, and approving, and removes the two venue-wide predicates so the
-- superseded rule cannot be reached for again.
--
-- Read access is not narrowed for anyone who could act: every person
-- can_approve_assignment admits already reaches the submission through the
-- admin branch, the approved-assignment branch, or isPriorityZero. Write access
-- is narrowed deliberately, and widens in one place -- a submission's editor may
-- now seat and approve any role on it without also volunteering in the
-- approving role, which is what can_approve_assignment already says they may do.
--------------------------------------------------------------------------------
-- submissions SELECT: drop the venue-wide approver branch.
--
-- It is not replaced with a submission-scoped equivalent because that would be
-- redundant: can_approve_assignment's admin branch is isAdmin(venue) below, and
-- both of its assignment branches require an approved assignment on this
-- submission, which the branch below it already covers.
--------------------------------------------------------------------------------
drop policy "admins, authors, assigned, and bidders can view submissions" on public.submissions;

create policy "admins, authors, assigned, and bidders can view submissions" on "public"."submissions" as permissive for
select
	to anon,
	authenticated using (
		public.isadmin (venue)
		or (
			(
				select
					auth.uid ()
			)=any (authors)
		)
		or exists (
			select
				volunteers.id
			from
				public.volunteers
			where
				volunteers.scholarid=(
					select
						auth.uid ()
				)
				and volunteers.accepted='accepted'::invited
				and volunteers.roleid=any (
					array(
						select
							roles.id
						from
							public.roles
						where
							roles.venueid=submissions.venue
							and roles.biddable=true
					)
				)
		)
		or exists (
			select
				assignments.id
			from
				public.assignments
			where
				assignments.submission=submissions.id
				and assignments.approved=true
				and assignments.scholar=(
					select
						auth.uid ()
				)
		)
		-- The venue's editors, whether or not they are venue admins and whether or not
		-- they are assigned to this submission yet. Every other branch above requires a
		-- foothold ON the submission, so a priority-0 volunteer who was not also an admin
		-- could not see an unassigned submission at all -- which made a submission
		-- waiting for an editor invisible to precisely the people meant to pick it up.
		-- Deliberately the more generous of the two editor rules: isPriorityZero asks only
		-- that the role be accepted, while can_claim_editor_role also requires the
		-- volunteer to be active, because seeing a venue's work is not the same as taking
		-- a piece of it on.
		or public.isPriorityZero (submissions.venue)
	);

--------------------------------------------------------------------------------
-- assignments SELECT: the approvers of THIS submission, not of the role.
--
-- This also closes a gap in the other direction. The chain walked upward from
-- the assignment's role, so a submission's priority-0 editor saw none of its
-- assignments unless they happened to sit in that chain -- the reason
-- submission_has_editor exists. can_approve_assignment gives the editor of a
-- submission every role on it.
--------------------------------------------------------------------------------
drop policy "assignees and approvers can see assignments" on public.assignments;

create policy "assignees and approvers can see assignments" on public.assignments for
select
	to authenticated using (
		(
			-- The assigned scholar can see their own assignment.
			(
				scholar=(
					select
						auth.uid () as "uid"
				)
			)
			-- Whoever may approve this assignment may see it, unless they are
			-- conflicted on the submission. can_approve_assignment covers venue
			-- admins itself.
			or (
				public.can_approve_assignment (submission, role)
				and not public.isConflicted (submission)
			)
			-- Open review: when the venue is not anonymous, the submission's
			-- authors may see who is assigned (unless they are conflicted).
			or (
				(
					select
						not anonymous_assignments
					from
						public.venues
					where
						id=venue
				)
				and public.isAuthor (submission)
				and not public.isConflicted (submission)
			)
		)
	);

--------------------------------------------------------------------------------
-- assignments UPDATE: approving or unassigning is for the approvers of this
-- submission. approveAssignment is a plain table update, so this policy was the
-- only thing standing between a venue-wide volunteer and every assignment in
-- the venue.
--------------------------------------------------------------------------------
drop policy "assignees and approvers can update assignments" on public.assignments;

create policy "assignees and approvers can update assignments" on public.assignments
for update
	to authenticated using (
		(
			(
				scholar=(
					select
						auth.uid () as "uid"
				)
			)
			or public.can_approve_assignment (submission, role)
		)
	);

--------------------------------------------------------------------------------
-- assignments INSERT: seating someone requires being able to approve them here.
--
-- The old branch paired the venue-wide check with isAssigned(submission), which
-- asks only for an approved assignment in SOME role on the submission -- so a
-- scholar seated as a plain reviewer, who also volunteered in the approving
-- role venue-wide, could seat further reviewers alongside themselves.
--
-- The approver seated on a submission may still seat anyone in the roles they
-- approve, including themselves; nothing here constrains who is being seated.
-- The bidding and claim-editor branches are unchanged.
--------------------------------------------------------------------------------
drop policy "admins, approvers and volunteers can create assignments" on public.assignments;

create policy "admins, approvers and volunteers can create assignments" on "public"."assignments" for insert to "authenticated"
with
	check (
		(
			-- Whoever may approve an assignment for this role on this submission may
			-- create one. Covers venue admins and the submission's editor.
			public.can_approve_assignment (submission, role)
			-- If the venue permits bidding and the volunteer has the role for which this assignment is being created.
			or (
				bid
				and (
					exists (
						select
						from
							public.volunteers
						where
							(
								(volunteers.roleid=assignments.role)
								and (
									volunteers.scholarid=(
										select
											auth.uid () as "uid"
									)
								)
								and volunteers.active
								and (volunteers.accepted='accepted')
							)
					)
				)
			)
			-- An editor of the venue claiming a submission nobody is editing yet. See
			-- public.can_claim_editor_role for why this branch has to exist and why it
			-- is drawn this narrowly; the checks here are the ones the function cannot
			-- make for itself, since it is not told who is being seated.
			or (
				scholar=(
					select
						auth.uid () as "uid"
				)
				and not bid
				and not completed
				and public.can_claim_editor_role (submission, role)
			)
		)
	);

--------------------------------------------------------------------------------
-- The venue-wide predicates now have no callers. Drop them rather than leave
-- two SECURITY DEFINER functions around that encode exactly the rule this
-- migration removes. isAssigned stays: the thanks SELECT policy still uses it.
--------------------------------------------------------------------------------
drop function public.isRoleApproverVolunteer (uuid);

drop function public.isInApproverChain (uuid);
