--------------------------------------
-- Schema
create table if not exists public.conflicts (
	-- The submission on for which there is a conflict
	submissionid uuid not null references submissions (id),
	-- The scholar for which there is a conflict
	scholarid uuid not null references scholars (id),
	-- The reason for the conflict
	reason text default ''::text not null,
	-- The primary key is joint
	constraint conflicts_pkey primary key (submissionid, scholarid)
);

alter table public.conflicts OWNER to "postgres";

grant all on table public.conflicts to "anon";

grant all on table public.conflicts to "authenticated";

grant all on table public.conflicts to "service_role";

--------------------------------------
-- Security
alter table public.conflicts ENABLE row LEVEL SECURITY;

create policy "anyone can see conflicts" on public.conflicts for
select
	to "authenticated" using (true);

create policy "admins and volunteers can create conflicts" on public.conflicts for INSERT to "authenticated",
"anon"
with
	check (
		(
			-- Scholar is editor of the submission's venue
			public.isAdmin (
				(
					select
						submissions.venue
					from
						public.submissions
					where
						(submissions.id=conflicts.submissionid)
				)
			)
		)
		or (
			-- Scholar is a volunteer for the submission's venue
			exists (
				select
					*
				from
					public.volunteers
				where
					(
						volunteers.scholarid=conflicts.scholarid
						and volunteers.roleid in (
							select
								roles.id
							from
								public.roles
							where
								(
									roles.venueid=(
										select
											submissions.venue
										from
											public.submissions
										where
											(submissions.id=conflicts.submissionid)
									)
								)
						)
					)
			)
		)
	);

create policy "admins can update conflicts" on public.conflicts
for update
	to "authenticated" using (
		public.isAdmin (
			(
				select
					submissions.venue
				from
					public.submissions
				where
					(submissions.id=conflicts.submissionid)
			)
		)
	);

create policy "admins can delete conflicts" on public.conflicts for DELETE to "authenticated" using (
	(
		(
			public.isAdmin (
				(
					select
						submissions.venue
					from
						public.submissions
					where
						(submissions.id=conflicts.submissionid)
				)
			)
		)
	)
);
