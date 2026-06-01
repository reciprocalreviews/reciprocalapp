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
	created_at timestamp with time zone default timezone ('utc'::text, now()) not null
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
add constraint "assignments_preferenceid_fkey" foreign KEY (preferenceid) references public.preference_levels (id) on delete set null;

--------------------------------------
-- Indexes
create index "assignments_scholar_index" on public.assignments using "btree" (scholar);

create index "assignments_submission_index" on public.assignments using "btree" (submission);

create index "idx_assignments_completed" on public.assignments using "btree" (completed);

--------------------------------------
-- Functions
create or replace function public.isApprover (_roleid uuid) RETURNS boolean LANGUAGE sql SECURITY DEFINER
set
	"search_path" to '' as $$
    select (
		exists (
			select id 
			from public.volunteers 
			where 
				scholarid = (select auth.uid()) and 
				roleid=(select approver from public.roles where id=_roleid) and 
				accepted = 'accepted'
		)
	)
$$;

alter function public.isApprover (_roleid uuid) OWNER to "postgres";

grant all on FUNCTION public.isApprover (_roleid uuid) to "anon";

grant all on FUNCTION public.isApprover (_roleid uuid) to "authenticated";

grant all on FUNCTION public.isApprover (_roleid uuid) to "service_role";

create or replace function public.isAssigned (_submissionid uuid) RETURNS boolean LANGUAGE sql SECURITY DEFINER
set
	"search_path" to '' as $$
	select (exists (select id from public.assignments where submission=_submissionid and scholar=(select auth.uid()) and approved=true))
$$;

alter function public.isAssigned (_submissionid uuid) OWNER to "postgres";

grant all on FUNCTION public.isAssigned (_submissionid uuid) to "anon";

grant all on FUNCTION public.isAssigned (_submissionid uuid) to "authenticated";

grant all on FUNCTION public.isAssigned (_submissionid uuid) to "service_role";

-- True if the current scholar is an accepted volunteer on any role in the
-- approver chain ABOVE the given role (its approver, that role's approver, and
-- so on). These are the scholars empowered to make/oversee assignments to the
-- role, so they may see its assignments. Walks roles.approver upward with a
-- depth guard to tolerate accidental cycles.
create or replace function public.isInApproverChain (_roleid uuid) RETURNS boolean LANGUAGE sql SECURITY DEFINER
set
	"search_path" to '' as $$
	with recursive chain as (
		select approver as roleid, 1 as depth
		from public.roles
		where id = _roleid and approver is not null
		union all
		select r.approver, c.depth + 1
		from public.roles r
		join chain c on r.id = c.roleid
		where r.approver is not null and c.depth < 50
	)
	select exists (
		select 1
		from public.volunteers v
		join chain c on c.roleid = v.roleid
		where v.scholarid = (select auth.uid()) and v.accepted = 'accepted'
	);
$$;

alter function public.isInApproverChain (_roleid uuid) OWNER to "postgres";

grant all on FUNCTION public.isInApproverChain (_roleid uuid) to "anon";

grant all on FUNCTION public.isInApproverChain (_roleid uuid) to "authenticated";

grant all on FUNCTION public.isInApproverChain (_roleid uuid) to "service_role";

-- True if the current scholar has a declared conflict of interest on the given
-- submission. plpgsql (not sql) so the body's reference to public.conflicts is
-- resolved at run time, since the conflicts table loads after this file.
create or replace function public.isConflicted (_submissionid uuid) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER
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
create or replace function public.isAuthor (_submissionid uuid) RETURNS boolean LANGUAGE sql SECURITY DEFINER
set
	"search_path" to '' as $$
	select exists (
		select 1
		from public.submissions
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
create policy "authors, assigned, and bidders can view submissions" on public.submissions for
select
	to authenticated using (
		(
			-- Authors can see their own submissions
			(
				(
					select
						auth.uid () as uid
				)=any (authors)
			)
			-- Volunteers with accepted biddable roles for the submission's venue
			or (
				exists (
					select
						volunteers.id
					from
						public.volunteers
					where
						(
							(
								volunteers.scholarid=(
									select
										auth.uid () as uid
								)
							)
							and (volunteers.accepted='accepted'::public.invited)
							and (
								volunteers.roleid=any (
									array(
										select
											roles.id
										from
											public.roles
										where
											(roles.venueid=submissions.venue)
											and roles.biddable=true
									)
								)
							)
						)
				)
			)
			-- Scholars assigned to the submission
			or (
				exists (
					select
						assignments.id
					from
						public.assignments
					where
						(
							(assignments.submission=submissions.id)
							and (assignments.approved=true)
							and (
								assignments.scholar=(
									select
										auth.uid () as uid
								)
							)
						)
				)
			)
		)
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
-- Otherwise, only the approver chain for the role (and venue admins) may see it,
-- and never if that viewer is conflicted on the submission.
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
			-- The approver chain for the role, or venue admins, may see it,
			-- unless they are conflicted on the submission.
			or (
				(
					public.isInApproverChain (role)
					or public.isAdmin (venue)
				)
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
			or public.isApprover (role)
		)
	);

create policy "assignees can delete assignments" on "public"."assignments" for delete to authenticated using (
	(
		scholar=(
			select
				auth.uid () as "uid"
		)
	)
);

create policy "admins, approvers and volunteers can create assignments" on "public"."assignments" for insert to "authenticated"
with
	check (
		(
			-- If the current scholar is an admin, they can create any assignment.
			public.isAdmin (venue)
			-- If the current scholar has an assigment to the role that is the approver for the new assignment's role.
			or (
				isApprover (role)
				and isAssigned (submission)
			)
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

create or replace trigger enforce_submission_author_edits before
update on public.submissions for each row
execute function public.enforce_submission_author_edits ();

grant all on table public.assignments to "anon";

grant all on table public.assignments to "authenticated";

grant all on table public.assignments to "service_role";

alter publication supabase_realtime
add table assignments;
