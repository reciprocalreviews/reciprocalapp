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
	-- Timestamp when the assignment was created
	created_at timestamp with time zone default timezone ('utc'::text, now()) not null
);

alter table public.assignments OWNER to "postgres";

alter table only public.assignments
add constraint "assignments_pkey" primary key (id);

alter table only public.assignments
add constraint "assignments_role_fkey" foreign KEY (role) references public.roles (id);

alter table only public.assignments
add constraint "assignments_scholar_fkey" foreign KEY (scholar) references public.scholars (id);

alter table only public.assignments
add constraint "assignments_submission_fkey" foreign KEY (submission) references public.submissions (id);

alter table only public.assignments
add constraint "assignments_venue_fkey" foreign KEY (venue) references public.venues (id);

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

--------------------------------------
-- Security
alter table public.assignments enable row level security;

-- We declare the select policy for submissions after the assigments table is created.
create policy "authors, editors, and bidders can view submissions" on public.submissions for
select
	to "authenticated",
	"anon" using (
		(
			-- Authors can see their own submissions
			(
				(
					select
						auth.uid () as uid
				)=any (authors)
			)
			-- Editors can see all submissions in their venue
			or public.isEditor (venue)
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

create policy "editors, assignees, and approvers can see assignments" on public.assignments for
select
	to "authenticated",
	"anon" using (
		(
			public.isEditor (venue)
			or (
				"scholar"=(
					select
						auth.uid () as "uid"
				)
			)
			or public.isAssigned (submission)
			or public.isApprover (role)
		)
	);

create policy "editors, assignees, and approvers can update assignments" on public.assignments
for update
	to "authenticated",
	"anon" using (
		(
			public.isEditor (venue)
			or (
				"scholar"=(
					select
						auth.uid () as "uid"
				)
			)
			or public.isApprover (role)
		)
	)
with
	check (true);

create policy "editors and assignees can delete assignments" on "public"."assignments" for delete to "authenticated" using (
	(
		public.isEditor (venue)
		or (
			"scholar"=(
				select
					auth.uid () as "uid"
			)
		)
	)
);

create policy "editors, approvers, and volunteers can create assignments" on "public"."assignments" for insert to "authenticated",
"anon"
with
	check (
		(
			public.isEditor (venue)
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

grant all on table public.assignments to "anon";

grant all on table public.assignments to "authenticated";

grant all on table public.assignments to "service_role";
