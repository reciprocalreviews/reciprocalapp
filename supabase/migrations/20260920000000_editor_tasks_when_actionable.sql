-- The Tasks table on a scholar's profile listed every submission their venue had ever
-- received, labelled "Review", to someone who was reviewing none of them.
--
-- Two causes, both fixed here. A venue with a sole editor seats that editor on every
-- submission (create_submission, bulk_import_submissions), and the seat stays approved and
-- uncompleted until mark_submission_done pays it -- so the page's "all my open assignments"
-- query returned the whole venue. And a reviewer who had finished and requested compensation
-- kept the paper on their own list until somebody else paid them.
--
-- scholar_tasks answers "which of my assignments is waiting on ME" instead. scholar_approver_roles
-- splits out the approver derivation, which the page used to compute from the very same array
-- it rendered -- so narrowing the task list would have silently deleted the approver's rows.
--
-- The `revoke execute ... from anon` below travels in THIS migration on purpose: Supabase's
-- default privileges re-grant EXECUTE to anon every time a function is created, so a revoke
-- left behind in an earlier migration is undone by this one. supabase/tests/rls/definer_grants.sql
-- check 1 is what catches it if this is ever forgotten.

-- What the signed-in scholar still has to do, as their profile's Tasks table renders it.
--
-- Two rules in one function, because they are one question: which of my assignments is
-- actually waiting on me?
--
-- 1. Work I have finished is not waiting on me. An assignment with compensation_requested_at
--    set is awaiting an APPROVER, and belongs on their list -- getAssignmentsAwaitingCompensation
--    already puts it there -- rather than on mine. supabase/functions/remind/index.ts draws the
--    same line for the same reason.
--
-- 2. A priority-0 (editor) assignment is seated on EVERY submission at a venue with a sole
--    editor: create_submission and bulk_import_submissions both do it, and the row stays
--    approved-and-uncompleted for the life of the paper, because only mark_submission_done
--    completes it. It is a standing seat, not a piece of work. Listing them all told an editor
--    their entire venue was a personal to-do list, labelled every paper in it a "review" they
--    were not doing, and buried the submissions that genuinely did need them. So an editor row
--    appears only when the submission is actually waiting on the editor:
--      'unstaffed' -- nobody is seated in a non-editor role yet, so review cannot start until
--                     the editor recruits or approves someone.
--      'ready'     -- every seated non-editor assignment is settled. That is exactly the
--                     blocker set mark_submission_done computes, so this list and that button
--                     can never disagree about whether a paper can be closed.
--    Anything between the two -- reviewers seated and working -- is waiting on the reviewers,
--    not on the editor, and drops off.
--
-- SECURITY DEFINER is load-bearing here rather than habitual, and for the same reason as
-- submission_has_editor above: whether a submission is waiting on its editor is an aggregate
-- over SIBLING assignment rows, and the assignments SELECT policy admits those to an editor
-- only `and not public.isConflicted(submission)`. Run as the caller, a conflicted editor would
-- see no siblings and every one of their submissions would report 'unstaffed' -- the dangerous
-- direction, since it is the one that puts rows back on the list. It reports only on the
-- caller's OWN assignments, so it discloses nothing they could not already select.
create or replace function public.scholar_tasks () returns table (
	assignment uuid,
	submission uuid,
	title text,
	venue uuid,
	role uuid,
	role_name text,
	priority integer,
	state text
) language sql security definer stable
set
	"search_path" to '' as $$
	with mine as (
		select a.id as assignment, a.submission, r.id as role, r.name as role_name, r.priority
		from public.assignments a
		join public.roles r on r.id = a.role
		where a.scholar = (select auth.uid())
			and a.approved
			and not a.completed
			and a.compensation_requested_at is null
	)
	select
		m.assignment,
		s.id,
		s.title,
		s.venue,
		m.role,
		m.role_name,
		m.priority,
		case
			when m.priority > 0 then 'assigned'
			when not exists (
				select 1
				from public.assignments o
				join public.roles orr on orr.id = o.role
				where o.submission = m.submission and o.approved and orr.priority > 0
			) then 'unstaffed'
			else 'ready'
		end
	from mine m
	join public.submissions s on s.id = m.submission
	where m.priority > 0
		or (
			s.status = 'reviewing'
			and not exists (
				select 1
				from public.assignments o
				join public.roles orr on orr.id = o.role
				where o.submission = m.submission
					and o.approved
					and not o.completed
					and orr.priority > 0
			)
		)
	order by s.created_at desc, m.assignment;
$$;

alter function public.scholar_tasks () OWNER to "postgres";

revoke
execute on function public.scholar_tasks ()
from
	public,
	anon;

grant
execute on function public.scholar_tasks () to authenticated;

-- The roles this scholar approves on, derived from the roles they themselves hold.
--
-- Deliberately its own query rather than a map over scholar_tasks. The profile load used to
-- fetch every assignment, render them as tasks, and map that same array to role ids -- so
-- narrowing what is DISPLAYED silently deleted the approver's "pending assignment" and
-- "compensation to approve" rows. They are different questions; they now have separate
-- answers, and the filter below is deliberately the OLD one -- no priority test and no
-- compensation_requested_at test -- so that narrowing the task list cannot reach it.
--
-- SECURITY INVOKER: roles is world-readable and the subquery reads only
-- scholar = auth.uid(), which the assignments SELECT policy's first branch always admits.
create or replace function public.scholar_approver_roles () returns table (role uuid) language sql security invoker stable
set
	"search_path" to '' as $$
	select distinct r.id
	from public.roles r
	where r.approver in (
		select a.role
		from public.assignments a
		where a.scholar = (select auth.uid()) and a.approved and not a.completed
	);
$$;

alter function public.scholar_approver_roles () OWNER to "postgres";

revoke
execute on function public.scholar_approver_roles ()
from
	public,
	anon;

grant
execute on function public.scholar_approver_roles () to authenticated;

