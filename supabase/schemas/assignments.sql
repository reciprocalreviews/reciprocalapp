--------------------------------------
-- Schema
-- Individuals who could be assigned to review a particular paper
create table if not exists public.assignments (
	-- The unique ID of the bid
	id uuid default gen_random_uuid() not null,
	-- The venue to which this assignment corresponds
	venue uuid not null,
	-- The submission bid on
	submission uuid not null,
	-- The scholar who bid
	scholar uuid not null,
	-- The role for which the bid occurred
	role uuid not null,
	-- True if a bid by the reviewer.
	bid boolean default false not null,
	-- True if the assignment has been approved
	approved boolean default false not null,
	-- True if the assignment has been completed
	completed boolean default false not null,
	-- The bidder's chosen preference level for this submission. Only meaningful
	-- when bid=true and the venue has defined preference levels; null otherwise.
	preferenceid uuid,
	-- Timestamp when the assignment was created
	created_at timestamp with time zone default timezone ('utc'::text, now()) not null,
	-- When the scholar requested compensation for this assignment (null until
	-- they do). Distinguishes finished work awaiting an approver from a review
	-- still in progress, so the daily remind function can nag approvers about
	-- the former without nagging them about the latter. Written by
	-- public.request_compensation, which also creates the row when the scholar has
	-- none: an unapproved, non-bid row carrying this stamp is a CLAIM, work done for
	-- a submission nobody on the platform seated them on (typically an imported one
	-- whose editor has not joined yet), waiting for an approver to approve and pay it
	-- in one step (complete_assignment) or decline it (decline_bid).
	compensation_requested_at timestamp with time zone default null,
	-- When an approver declined this bid or claim (null unless declined). A bid has three states:
	-- pending (bid, not approved, not declined), approved, and declined. Declining is a
	-- courtesy an approver may extend -- a bid sets no expectation of a reply, so leaving it
	-- alone is always allowed -- but a decline is an explicit signal to a person, so it is
	-- never silent: decline_reason is required and is sent to the bidder. Written only by
	-- public.decline_bid, and cleared when an approver approves the bid after all.
	declined_at timestamp with time zone default null,
	-- Who declined it. Nulled if that scholar is erased; the decline itself stands.
	declined_by uuid default null,
	-- The approver's explanation, sent to the bidder. Required whenever declined_at is set.
	decline_reason text default null,
	constraint assignments_decline_shape_check check ((declined_at is null)=(decline_reason is null)),
	constraint assignments_decline_reason_check check (
		decline_reason is null
		or char_length(btrim(decline_reason)) between 1 and 1000
	),
	constraint assignments_decline_only_bids_check check (
		declined_at is null
		or (
			(
				bid
				or compensation_requested_at is not null
			)
			and not approved
			and not completed
		)
	)
);

alter table public.assignments OWNER to "postgres";

alter table only public.assignments
add constraint "assignments_pkey" primary key (id);

alter table only public.assignments
add constraint "assignments_role_fkey" foreign KEY (role) references public.roles (id) on delete cascade;

alter table only public.assignments
add constraint "assignments_scholar_fkey" foreign KEY (scholar) references public.scholars (id) on delete cascade;

alter table only public.assignments
add constraint "assignments_submission_fkey" foreign KEY (submission) references public.submissions (id) on delete cascade;

alter table only public.assignments
add constraint "assignments_venue_fkey" foreign KEY (venue) references public.venues (id) on delete cascade;

alter table only public.assignments
add constraint "assignments_declined_by_fkey" foreign KEY (declined_by) references public.scholars (id) on delete set null;

alter table only public.assignments
add constraint "assignments_preferenceid_fkey" foreign KEY (preferenceid) references public.preference_levels (id) on delete set null;

--------------------------------------
-- Indexes
create index "assignments_scholar_index" on public.assignments using "btree" (scholar);

create index "assignments_submission_index" on public.assignments using "btree" (submission);

create index "idx_assignments_completed" on public.assignments using "btree" (completed);

--------------------------------------
-- Functions
-- The single definition of "may this scholar approve an assignment for this role
-- on this submission" — a venue admin, the submission's priority-0 editor, or the
-- holder of the approving role, each requiring an APPROVED ASSIGNMENT on this
-- submission. Mirrored in TypeScript by src/lib/data/canApproveAssignment.ts.
create or replace function public.can_approve_assignment (_submission uuid, _role uuid) returns boolean language sql security definer STABLE
set
	search_path to '' as $$
	select exists (
		-- A venue admin can approve anything in their venue.
		select 1
		from public.submissions s
		where s.id = _submission and public.isAdmin(s.venue)
	) or exists (
		-- The priority-0 editor OF THIS SUBMISSION can approve any role on it.
		select 1
		from public.assignments a
		join public.roles r on r.id = a.role
		where a.submission = _submission
		  and a.scholar = (select auth.uid())
		  and a.approved
		  and r.priority = 0
	) or exists (
		-- Whoever holds the role that approves the role in question, on this submission.
		select 1
		from public.assignments a
		join public.roles target on target.id = _role
		where a.submission = _submission
		  and a.scholar = (select auth.uid())
		  and a.approved
		  and target.approver is not null
		  and a.role = target.approver
	);
$$;

alter function public.can_approve_assignment (uuid, uuid) OWNER to "postgres";

revoke
execute on function public.can_approve_assignment (uuid, uuid)
from
	public;

grant
execute on function public.can_approve_assignment (uuid, uuid) to authenticated;

-- Who is told that a bid arrived: the people who will answer it, not everyone who
-- edits the venue. Mailing every admin and priority-0 volunteer about every bid buried
-- the people who could act on it in mail about submissions they had nothing to do with.
--
-- Only whoever holds the bid-on role's approving role on this submission -- the
-- approver branch of can_approve_assignment above -- minus the bidder and anyone
-- conflicted on the submission. There is deliberately no fallback. It used to fall to the
-- submission's priority-0 editor and then the venue's admins, which mailed an
-- editor-in-chief seated on every submission about every bid on a submission that had no
-- associate editor yet. With nobody to tell, nobody is told: the bid waits in the
-- submission's pending count for whoever seats an approver, and a role with no approver
-- configured sends no bid mail at all.
--
-- SECURITY DEFINER because the bidder cannot see the approvers' assignments, and gated
-- on the caller having bid for this role on this submission, so it cannot be used to
-- learn who reviews or edits a submission one has no part in. plpgsql rather than sql so
-- the body is not resolved at creation: public.conflicts is declared after this file.
create or replace function public.bid_notice_recipients (_submission uuid, _role uuid) returns setof uuid language plpgsql security definer STABLE
set
	search_path to '' as $$
begin
	return query
	select distinct a.scholar
	from public.assignments a
	join public.roles target on target.id = _role
	where a.submission = _submission
	  and a.approved
	  and a.role = target.approver
	  and a.scholar <> (select auth.uid())
	  and not exists (
		select 1
		from public.conflicts x
		where x.submissionid = _submission and x.scholarid = a.scholar
	  )
	  and exists (
		select 1
		from public.assignments b
		where b.submission = _submission
		  and b.role = _role
		  and b.bid
		  and b.scholar = (select auth.uid())
	  );
end;
$$;

alter function public.bid_notice_recipients (uuid, uuid) OWNER to "postgres";

-- Explicitly revoked, not merely un-granted: Supabase's ALTER DEFAULT PRIVILEGES hands anon
-- EXECUTE on every function created in `public` at creation time.
revoke
execute on function public.bid_notice_recipients (uuid, uuid)
from
	public,
	anon;

grant
execute on function public.bid_notice_recipients (uuid, uuid) to authenticated;

-- The second rule in this family, and deliberately not the same question as the one
-- above: "may I take this submission?", not "may I approve it for someone else?".
--
-- It exists because the venue's own editors could not seat themselves. The priority-0
-- role has no approver, so the approver branch of can_approve_assignment is never true
-- for it, and its editor branch requires an approved priority-0 assignment on the very
-- submission being claimed — which is self-perpetuating. That left isAdmin() as
-- the only way anyone became the first editor on a submission, so an Editor-role
-- volunteer who was not also a venue admin could be told a submission needed them and be
-- unable to do anything about it.
--
-- Narrow on every axis: the caller only, the venue's priority-0 role only, and only while
-- the submission has no priority-0 assignment at all. It cannot seat anyone else, seat
-- anyone in another role, or displace an editor who is already there.
--
-- SECURITY DEFINER is load-bearing rather than habitual: the emptiness test reads
-- public.assignments, which is itself RLS-gated, so the same test written inline in the
-- policy would see only the rows the claimer may select and would report "no editor" for
-- a submission that already has one. Mirrored in TypeScript by
-- src/lib/data/canClaimEditor.ts.
create or replace function public.can_claim_editor_role (_submission uuid, _role uuid) returns boolean language sql security definer STABLE
set
	search_path to '' as $$
	select exists (
		select 1
		from public.submissions s
		join public.roles r
			on r.id = _role and r.venueid = s.venue and r.priority = 0
		join public.volunteers v
			on v.roleid = r.id
			and v.scholarid = (select auth.uid())
			and v.active
			and v.accepted = 'accepted'
		where s.id = _submission
		  and not exists (
				select 1
				from public.assignments a
				join public.roles ar on ar.id = a.role
				where a.submission = _submission and ar.priority = 0
			)
	);
$$;

alter function public.can_claim_editor_role (uuid, uuid) OWNER to "postgres";

revoke
execute on function public.can_claim_editor_role (uuid, uuid)
from
	public;

grant
execute on function public.can_claim_editor_role (uuid, uuid) to authenticated;

-- Whether a submission has anyone in a priority-0 role, and nothing else about who.
--
-- The venue's editors can see their venue's submissions but none of its assignments, so
-- the submissions list had no way to tell whether a submission already had an editor —
-- it inferred from the assignment rows it could see, and for a non-admin editor that is
-- none of them, so every submission looked unclaimed. Widening the assignments policy
-- would have handed reviewer identities to more people to answer a yes/no question, so
-- this answers the question instead.
--
-- SECURITY DEFINER, so it sees past the assignments policy; the pair below is what keeps
-- that narrow. It discloses one bit, and only about a submission whose id the caller
-- already holds.
create or replace function public.submission_has_editor (_submission uuid) returns boolean language sql security definer stable
set
	"search_path" to '' as $$
	select exists (
		select 1
		from public.assignments a
		join public.roles r on r.id = a.role
		where a.submission = _submission and r.priority = 0
	);
$$;

alter function public.submission_has_editor (uuid) OWNER to "postgres";

revoke
execute on function public.submission_has_editor (uuid)
from
	public;

grant
execute on function public.submission_has_editor (uuid) to authenticated;

-- Whether the submission's editor has closed bidding on it.
--
-- The assignments INSERT policy needs this, and cannot read public.submissions itself:
-- the submissions SELECT policy reads public.assignments, so the policy would recurse.
-- SECURITY DEFINER, so it sees past both. It discloses one bit, about a submission whose
-- id the caller already holds.
create or replace function public.submission_bidding_closed (_submission uuid) returns boolean language sql security definer stable
set
	"search_path" to '' as $$
	select coalesce(
		(select s.bidding_closed from public.submissions s where s.id = _submission),
		false
	);
$$;

alter function public.submission_bidding_closed (uuid) OWNER to "postgres";

-- The INSERT policy is granted to authenticated only, so anon needs no EXECUTE.
revoke
execute on function public.submission_bidding_closed (uuid)
from
	public,
	anon;

grant
execute on function public.submission_bidding_closed (uuid) to authenticated;

-- Open or close bidding on a submission that is still under review.
--
-- Whoever may answer bids on the submission may do this: whoever passes
-- can_approve_assignment for some biddable role at its venue -- a venue admin, the
-- submission's priority-0 editor, or the holder of a bid-approving role seated on it,
-- such as its Associate Editor. The flag is the submission's, so closing it closes
-- bidding in every role.
--
-- An RPC rather than a column grant because the submissions UPDATE policy admits
-- authors and editors only, and widening it to approvers would hand them the title,
-- type and expertise as well. bidding_closed is therefore left out of the column grant,
-- like status, and this is the only client path that writes it.
create or replace function public.set_submission_open_for_bidding (_submission uuid, _open boolean) returns void language plpgsql security definer
set
	"search_path" to '' as $$
begin
	if (select auth.uid()) is null then
		raise exception 'Authentication required' using errcode = '42501';
	end if;

	if not exists (
		select 1
		from public.submissions s
		join public.roles r on r.venueid = s.venue
		where s.id = _submission
			and r.biddable
			and public.can_approve_assignment(_submission, r.id)
	) then
		raise exception 'Only someone who may answer bids on this submission may open or close its bidding'
			using errcode = '42501';
	end if;

	update public.submissions set bidding_closed = not _open where id = _submission;
end;
$$;

alter function public.set_submission_open_for_bidding (uuid, boolean) OWNER to "postgres";

revoke
execute on function public.set_submission_open_for_bidding (uuid, boolean)
from
	public,
	anon;

grant
execute on function public.set_submission_open_for_bidding (uuid, boolean) to authenticated;

-- The list form, and the one the application actually calls. SECURITY INVOKER, so the
-- scan of public.submissions runs under the caller's own policy: a caller gets exactly
-- one row per submission they may already see, each carrying that one bit.
create or replace function public.venue_submission_editors (_venue uuid) returns table (submission uuid, has_editor boolean) language sql security invoker stable
set
	"search_path" to '' as $$
	select s.id, public.submission_has_editor(s.id)
	from public.submissions s
	where s.venue = _venue;
$$;

alter function public.venue_submission_editors (uuid) OWNER to "postgres";

revoke
execute on function public.venue_submission_editors (uuid)
from
	public;

grant
execute on function public.venue_submission_editors (uuid) to authenticated;

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

create or replace function public.isAssigned (_submissionid uuid) RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE
set
	"search_path" to '' as $$
	select (exists (select id from public.assignments where submission=_submissionid and scholar=(select auth.uid()) and approved=true))
$$;

alter function public.isAssigned (_submissionid uuid) OWNER to "postgres";

grant all on FUNCTION public.isAssigned (_submissionid uuid) to "anon";

grant all on FUNCTION public.isAssigned (_submissionid uuid) to "authenticated";

grant all on FUNCTION public.isAssigned (_submissionid uuid) to "service_role";

-- True if the current scholar has a declared conflict of interest on the given
-- submission. plpgsql (not sql) so the body's reference to public.conflicts is
-- resolved at run time, since the conflicts table loads after this file.
create or replace function public.isConflicted (_submissionid uuid) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER STABLE
set
	"search_path" to '' as $$
begin
	return exists (
		select 1
		from public.conflicts
		where submissionid = _submissionid and scholarid = (select auth.uid())
	);
end;
$$;

alter function public.isConflicted (_submissionid uuid) OWNER to "postgres";

grant all on FUNCTION public.isConflicted (_submissionid uuid) to "anon";

grant all on FUNCTION public.isConflicted (_submissionid uuid) to "authenticated";

grant all on FUNCTION public.isConflicted (_submissionid uuid) to "service_role";

-- True if the current scholar is an author of the given submission. SECURITY
-- DEFINER so the assignments SELECT policy can read submissions.authors without
-- triggering the submissions RLS policy (which itself reads assignments — that
-- mutual reference would otherwise be infinite recursion).
create or replace function public.isAuthor (_submissionid uuid) returns boolean language sql security definer STABLE
set
	"search_path" to '' as $$
	select exists (
		select 1 from public.submissions
		where id = _submissionid and (select auth.uid()) = any (authors)
	);
$$;

alter function public.isAuthor (_submissionid uuid) OWNER to "postgres";

grant all on FUNCTION public.isAuthor (_submissionid uuid) to "anon";

grant all on FUNCTION public.isAuthor (_submissionid uuid) to "authenticated";

grant all on FUNCTION public.isAuthor (_submissionid uuid) to "service_role";

--------------------------------------
-- Security
alter table public.assignments enable row level security;

-- We declare the select policy for submissions after the assigments table is created.
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
		or (
			-- An accepted volunteer on a biddable role, deciding what to bid on...
			exists (
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
			-- ...but only while the submission is open for bidding, unless the bidder
			-- already has an assignment on it (a pending bid, say), which should not
			-- point at a submission they can no longer open.
			and (
				not submissions.bidding_closed
				or exists (
					select
						assignments.id
					from
						public.assignments
					where
						assignments.submission=submissions.id
						and assignments.scholar=(
							select
								auth.uid ()
						)
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

-- We declare the submissions update policy after the assignments table is created
-- So we can refer to the assignments.
create policy "authors and editors can update submissions" on public.submissions
for update
	to authenticated using (
		-- The authenticated scholar has a top priority role on this submission
		(
			exists (
				select
					id
				from
					public.assignments
				where
					assignments.submission=submissions.id
					and scholar=(
						select
							auth.uid ()
					)
					and approved=true
					and exists (
						select
							id
						from
							public.roles
						where
							id=assignments.role
							and priority=0
					)
			)
		)
		-- The authenticated scholar is an author on this submission
		or (
			(
				select
					auth.uid ()
			)=any (authors)
		)
	);

-- Assignment visibility: the assigned scholar always sees their own assignment.
-- Otherwise, only whoever may approve it on this submission may see it -- a venue
-- admin, the submission's editor, or the holder of the approving role on it -- and
-- never if that viewer is conflicted on the submission.
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
			-- authors may see who is assigned (unless they are conflicted). Only
			-- who is ASSIGNED: a pending or declined bid is a conversation between
			-- the bidder and the approvers, and a declined one carries the
			-- approver's reasons for turning a reviewer down.
			or (
				approved
				and (
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

-- A declined bid cannot be deleted by its bidder. The decline stands as the record of
-- the approver's answer, and deleting it would also let the bidder bid again as if it
-- had never been answered. An approver reverses a decline by approving the bid.
create policy "assignees can delete assignments" on "public"."assignments" for delete to authenticated using (
	(
		scholar=(
			select
				auth.uid () as "uid"
		)
		and declined_at is null
	)
);

create policy "admins, approvers and volunteers can create assignments" on "public"."assignments" for insert to "authenticated"
with
	check (
		(
			-- Whoever may approve an assignment for this role on this submission may
			-- create one. Covers venue admins and the submission's editor.
			--
			-- The old rule paired a venue-wide approver check with isAssigned, which
			-- asks only for an approved assignment in SOME role on the submission --
			-- so a scholar seated as a plain reviewer, who also volunteered in the
			-- approving role venue-wide, could seat further reviewers alongside
			-- themselves. The approver seated here may still seat anyone in the roles
			-- they approve, including themselves.
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
				-- The editor may close bidding on a submission that is still under review.
				and not public.submission_bidding_closed (submission)
			)
			-- An editor of the venue claiming a submission nobody is editing yet. See
			-- public.can_claim_editor_role above for why this branch has to exist and
			-- why it is drawn this narrowly; the checks here are the ones the function
			-- cannot make for itself, since it is not told who is being seated.
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

-- The submissions UPDATE policy lets authors edit their submission, but authors
-- must NOT be able to change the author list (authors/payments/transactions);
-- only a priority-0 assigned scholar on the paper may. RLS using-clauses cannot
-- be column-specific, so enforce the author-list lock with a BEFORE UPDATE
-- trigger (mirrors the revoke-update lock on submissions.status/completed_at).
create or replace function public.enforce_submission_author_edits () RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
set
	"search_path" to '' as $$
begin
	if (
		new.authors is distinct from old.authors
		or new.payments is distinct from old.payments
		or new.transactions is distinct from old.transactions
	) and not exists (
		select 1
		from public.assignments a
		join public.roles r on r.id = a.role
		where a.submission = old.id
			and a.scholar = (select auth.uid())
			and a.approved = true
			and r.priority = 0
	) then
		raise exception 'Only priority-0 assigned scholars may change the author list';
	end if;
	return new;
end;
$$;

alter function public.enforce_submission_author_edits () OWNER to "postgres";

create or replace trigger enforce_submission_author_edits
before update on public.submissions for each row
execute function public.enforce_submission_author_edits ();

-- The UPDATE policy above admits the assignee's own row with no limit on columns, because
-- RLS cannot be column-specific -- which let an assignee approve their own bid, complete
-- their own assignment, or move it to another role or submission. So, per column:
--
--   * scholar, role, submission, venue and bid never change after insert. An assignment is
--     about one person in one role on one paper; a different one is a different row.
--   * approved, completed and the decline columns are the approver's to set, under the
--     same rule as everything else an approver does: public.can_approve_assignment. An
--     approver who is also the assignee still passes, so seating oneself keeps working.
--   * preferenceid and compensation_requested_at are the assignee's own, and are the only
--     columns the app writes on its own row.
--
-- Approving a declined bid clears the decline: it is how an approver changes their mind,
-- and the decline-only-bids check would otherwise refuse the approval.
--
-- SECURITY INVOKER and gated on current_user = 'authenticated' on purpose. The SECURITY
-- DEFINER RPCs that write this table (complete_assignment, mark_submission_done,
-- decline_bid) run as postgres and authorize the caller themselves; this guards the one
-- path that has no other check, a client writing the row directly.
create or replace function public.enforce_assignment_updates () RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER
set
	"search_path" to '' as $$
begin
	if new.approved and not old.approved then
		new.declined_at := null;
		new.declined_by := null;
		new.decline_reason := null;
	end if;

	if current_user <> 'authenticated' then
		return new;
	end if;

	if (new.scholar, new.role, new.submission, new.venue, new.bid)
		is distinct from (old.scholar, old.role, old.submission, old.venue, old.bid) then
		raise exception 'An assignment''s scholar, role, submission and bid cannot be changed'
			using errcode = 'RR018';
	end if;

	if (new.approved, new.completed, new.declined_at, new.declined_by, new.decline_reason)
		is distinct from (old.approved, old.completed, old.declined_at, old.declined_by, old.decline_reason)
		and not public.can_approve_assignment(old.submission, old.role) then
		raise exception 'Only an approver of this role may approve, complete or decline this assignment'
			using errcode = 'RR018';
	end if;

	return new;
end;
$$;

alter function public.enforce_assignment_updates () OWNER to "postgres";

revoke
execute on function public.enforce_assignment_updates ()
from
	public,
	anon;

create or replace trigger enforce_assignment_updates
before update on public.assignments for each row
execute function public.enforce_assignment_updates ();

-- decline_bid: an approver answers a bid with no, and says why.
--
-- The SECURITY DEFINER write path for the decline columns; enforce_assignment_updates
-- above refuses them to direct client writes from anyone who cannot approve. Requires a
-- reason because a decline is addressed to a person, and the reason is what makes it a
-- principled answer rather than a door shut in someone's face. Returns what the client
-- needs to send the BidDeclined notice.
--
-- RR017 when the bid is no longer pending (approved, completed, or already declined),
-- which is the race two approvers answering the same bid would otherwise both win.
create or replace function public.decline_bid (_assignment uuid, _reason text) returns jsonb language plpgsql security definer
set
	search_path to '' as $$
declare
	_caller uuid;
	_a public.assignments;
	_trimmed text;
begin
	_caller := (select auth.uid());
	if _caller is null then
		raise exception 'Authentication required';
	end if;

	select * into _a from public.assignments where id = _assignment for update;
	if not found then
		raise exception 'Bid not found';
	end if;

	if not public.can_approve_assignment(_a.submission, _a.role)
		or public.isConflicted(_a.submission) then
		raise exception 'You are not authorized to decline this bid';
	end if;

	-- A pending claim (see compensation_requested_at) is answered the same way: it is
	-- also somebody asking an approver for something, and a no needs a reason.
	if not (_a.bid or _a.compensation_requested_at is not null)
		or _a.approved or _a.completed or _a.declined_at is not null then
		raise exception 'This bid is no longer pending' using errcode = 'RR017';
	end if;

	_trimmed := btrim(coalesce(_reason, ''));
	if char_length(_trimmed) = 0 then
		raise exception 'A declined bid needs an explanation for the bidder';
	end if;
	if char_length(_trimmed) > 1000 then
		raise exception 'An explanation must be at most 1000 characters';
	end if;

	update public.assignments
	set declined_at = now(), declined_by = _caller, decline_reason = _trimmed
	where id = _assignment;

	return jsonb_build_object(
		'venue', _a.venue,
		'submission', _a.submission,
		'scholar', _a.scholar,
		'role', _a.role
	);
end;
$$;

alter function public.decline_bid (uuid, text) OWNER to "postgres";

revoke
execute on function public.decline_bid (uuid, text)
from
	public,
	anon;

grant
execute on function public.decline_bid (uuid, text) to authenticated;

-- request_compensation: a scholar says they finished work on a submission and asks to
-- be paid for it.
--
-- Found by the venue's own manuscript ID, because that is what the venue's reviewing
-- system shows the scholar, and scoped to the venue, because manuscript IDs are only
-- unique within one. SECURITY DEFINER because the scholar may not be able to see the
-- submission at all: a backlog submission imported before its editor joined has nobody
-- on the platform who could have seated them, and reviewers in a role without bidding
-- see nothing they are not assigned to.
--
-- With an assignment already in place, this only stamps compensation_requested_at.
-- Without one, it files a CLAIM: an unapproved, non-bid assignment stamped the same
-- way, which any approver may approve and pay in one step (complete_assignment) or
-- decline with a reason (decline_bid). Filing one requires being an accepted volunteer
-- in the role -- active or not, since this is past work -- and not an author of the
-- submission. A claim cannot be filed in a priority-0 role: an editor seat carries
-- authority over the submission, and editors are paid by marking it done.
--
-- Returns the submission and everyone who may act on the request, the union of
-- can_approve_assignment's three branches minus the requester and anyone conflicted.
-- Computed here because the requester cannot see the other assignments that answer it.
create or replace function public.request_compensation (_venue uuid, _externalid text, _role uuid) returns jsonb language plpgsql security definer
set
	search_path to '' as $$
declare
	_caller uuid;
	_submission uuid;
	_priority integer;
	_a public.assignments;
	_recipients uuid[];
begin
	_caller := (select auth.uid());
	if _caller is null then
		raise exception 'Authentication required';
	end if;

	select s.id into _submission
	from public.submissions s
	where s.venue = _venue and s.externalid = btrim(coalesce(_externalid, ''));
	if _submission is null then
		raise exception 'No submission with that manuscript ID at this venue'
			using errcode = 'RR020';
	end if;

	select r.priority into _priority
	from public.roles r
	where r.id = _role and r.venueid = _venue;
	if _priority is null then
		raise exception 'That role does not belong to this venue';
	end if;

	select * into _a
	from public.assignments a
	where a.submission = _submission and a.role = _role and a.scholar = _caller
	limit 1
	for update;

	if found then
		if _a.completed then
			raise exception 'This work has already been compensated' using errcode = 'RR021';
		end if;
		if _a.declined_at is not null then
			raise exception 'This request was declined' using errcode = 'RR022';
		end if;
		update public.assignments
		set compensation_requested_at = coalesce(compensation_requested_at, now())
		where id = _a.id;
	else
		if _priority = 0 then
			raise exception 'Editors are compensated by marking a submission done'
				using errcode = 'RR023';
		end if;

		if not exists (
			select 1
			from public.volunteers v
			where v.roleid = _role
				and v.scholarid = _caller
				and v.accepted = 'accepted'
		) then
			raise exception 'Only volunteers in this role can request compensation for it'
				using errcode = 'RR024';
		end if;

		if exists (
			select 1 from public.submissions s
			where s.id = _submission and _caller = any (s.authors)
		) then
			raise exception 'Authors cannot request compensation for their own submission'
				using errcode = 'RR024';
		end if;

		insert into public.assignments (venue, submission, scholar, role, bid, approved, compensation_requested_at)
		values (_venue, _submission, _caller, _role, false, false, now());
	end if;

	select coalesce(array_agg(distinct x.scholar), array[]::uuid[]) into _recipients
	from (
		select a.scholar
		from public.assignments a
		join public.roles target on target.id = _role
		where a.submission = _submission and a.approved and a.role = target.approver
		union
		select a.scholar
		from public.assignments a
		join public.roles r on r.id = a.role
		where a.submission = _submission and a.approved and r.priority = 0
		union
		select unnest(v.admins)
		from public.venues v
		where v.id = _venue
	) x
	where x.scholar <> _caller
		and not exists (
			select 1 from public.conflicts c
			where c.submissionid = _submission and c.scholarid = x.scholar
		);

	return jsonb_build_object('submission', _submission, 'recipients', to_jsonb(_recipients));
end;
$$;

alter function public.request_compensation (uuid, text, uuid) OWNER to "postgres";

revoke
execute on function public.request_compensation (uuid, text, uuid)
from
	public,
	anon;

grant
execute on function public.request_compensation (uuid, text, uuid) to authenticated;

grant all on table public.assignments to "anon";

grant all on table public.assignments to "authenticated";

grant all on table public.assignments to "service_role";

alter publication supabase_realtime
add table assignments;

--------------------------------------
-- RPC (authoritative definition from migration 20260804020000_token_event_attribution)
create or replace function public.complete_assignment (
	_assignment_id uuid,
	_payment_purpose_template text,
	_mint_purpose_template text
) returns jsonb language plpgsql security definer
set
	search_path=public,
	pg_temp as $function$
declare
    _caller uuid;
    _assignment public.assignments;
    _role public.roles;
    _venue public.venues;
    _submission public.submissions;
    _amount integer;
    _available integer;
    _token_ids uuid[];
    _txn_id uuid;
    _mint_txn_id uuid;
    _shortfall integer;
    _mint_purpose text;
    _payment_purpose text;
begin
    _caller := (select auth.uid());
    if _caller is null then
        raise exception 'Authentication required';
    end if;

    select * into _assignment from public.assignments where id = _assignment_id;
    if not found then
        raise exception 'Assignment not found';
    end if;
    if _assignment.completed then
        raise exception 'Assignment is already completed';
    end if;
    -- A claim is the one unapproved assignment that may be completed: the scholar has
    -- said the work is done, so approving it and paying for it are one decision, and the
    -- update below records both. That includes a declined claim, which is how an approver
    -- changes their mind -- approving clears the decline (enforce_assignment_updates).
    if not _assignment.approved and _assignment.compensation_requested_at is null then
        raise exception 'Assignment must be approved before it can be completed';
    end if;

    select * into _role from public.roles where id = _assignment.role;
    if not found then
        raise exception 'Role not found';
    end if;

    -- Authorize the caller against the single definition of the rule. The same
    -- three branches are asserted in TypeScript by canApproveAssignment.unit.ts
    -- and in SQL by atomic_crud_rpc.sql, over the same table of cases.
    if not public.can_approve_assignment(_assignment.submission, _assignment.role) then
        raise exception 'You are not authorized to compensate this assignment';
    end if;

    select * into _venue from public.venues where id = _assignment.venue;
    if not found then
        raise exception 'Venue not found';
    end if;

    select * into _submission from public.submissions where id = _assignment.submission;
    if not found then
        raise exception 'Submission not found';
    end if;

    select amount into _amount from public.compensation
        where role = _assignment.role and submission_type = _submission.submission_type;
    if _amount is null then
        raise exception 'No compensation amount is configured for this role and submission type';
    end if;

    -- Substitute named placeholders in the localized purpose template.
    -- Supported placeholders: {role}, {title}, {amount}, {shortfall}.
    _payment_purpose := replace(
        replace(_payment_purpose_template, '{role}', _role.name),
        '{title}', _submission.title
    );

    -- How many tokens does the venue actually hold in this currency?
    select count(*) into _available from public.tokens
        where venue = _assignment.venue and currency = _venue.currency;

    if _available < _amount then
        _shortfall := _amount - _available;
        _mint_purpose := replace(
            replace(
                replace(
                    replace(_mint_purpose_template, '{amount}', _amount::text),
                    '{role}', _role.name
                ),
                '{title}', _submission.title
            ),
            '{shortfall}', _shortfall::text
        );

        -- Record a proposed mint so the minter has a pre-explained item to
        -- approve in the venue transactions page.
        insert into public.transactions (
            creator, from_scholar, from_venue, to_scholar, to_venue,
            tokens, currency, purpose, status
        ) values (
            _caller, null, null, null, _assignment.venue,
            array_fill('00000000-0000-0000-0000-000000000000'::uuid, array[_shortfall]),
            _venue.currency, _mint_purpose, 'proposed'
        ) returning id into _mint_txn_id;

        return jsonb_build_object(
            'status', 'insufficient',
            'shortfall', _shortfall,
            'amount', _amount,
            'mint_transaction_id', _mint_txn_id,
            'venue_id', _assignment.venue,
            'venue_title', _venue.title,
            'currency_id', _venue.currency,
            'scholar_id', _assignment.scholar,
            'submission_id', _assignment.submission,
            'role_name', _role.name
        );
    end if;

    -- Attribute the payout to its transaction. Generated up front: the tokens
    -- move before the transaction row exists, and the token_events trigger reads
    -- app.txn at the moment of the write.
    _txn_id := gen_random_uuid();
    perform set_config('app.txn', _txn_id::text, true);

    -- Take the tokens under lock and reassign them to the scholar. The count
    -- above decided whether to propose a mint; this can still come up short if a
    -- concurrent payout holds the rows it counted, which RR003 reports as a
    -- retryable shortfall rather than paying out tokens the venue no longer has.
    _token_ids := public._move_tokens(
        _venue.currency, null, _assignment.venue, _assignment.scholar, null,
        _amount, 'Insufficient tokens to compensate this assignment'
    );

    -- Record the approved transaction.
    insert into public.transactions (
        id, creator, from_scholar, from_venue, to_scholar, to_venue,
        tokens, currency, purpose, status
    ) values (
        _txn_id, _caller, null, _assignment.venue, _assignment.scholar, null,
        _token_ids, _venue.currency, _payment_purpose, 'approved'
    );

    perform set_config('app.txn', '', true);

    -- Mark the assignment completed, approving a claim along the way.
    update public.assignments set approved = true, completed = true where id = _assignment_id;

    return jsonb_build_object(
        'status', 'transferred',
        'transaction_id', _txn_id,
        'amount', _amount,
        'role_name', _role.name,
        'venue_id', _assignment.venue,
        'scholar_id', _assignment.scholar,
        'submission_id', _assignment.submission
    );
end;
$function$;
