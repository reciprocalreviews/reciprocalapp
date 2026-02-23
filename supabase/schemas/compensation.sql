/* SCHEMA  */
-- The types of submissions that a venue accepts, including resubmission types.
create table if not exists compensation (
	-- The submission type that this compensation corresponds to
	submission_type uuid not null references submission_types (id) on delete cascade,
	-- The role for which this compensation applies
	role uuid not null references roles (id) on delete cascade,
	-- The amount of compensation for this role and submission type, or null if the role is not compensated for this submission type.
	amount integer,
	-- The rationale for the amount of compensation, for transparency with scholars
	rationale text not null default ''::text,
	-- Composite primary key on submission type and role, as each role can only have one compensation amount per submission type, and each submission type can only have one compensation amount per role.
	primary key (submission_type, role)
);

alter table public.compensation OWNER to "postgres";

grant all on table public.compensation to "anon";

grant all on table public.compensation to "authenticated";

grant all on table public.compensation to "service_role";

--------------------------------------
-- Security
alter table public.compensation ENABLE row LEVEL SECURITY;

-- Venue admins define compensation.
create policy "venue admins can insert compensation" on public.compensation for insert to authenticated
with
	check (
		public.isAdmin (
			(
				select
					venueid
				from
					roles
				where
					roles.id=compensation.role
			)
		)
	);

-- Anyone can see compensation.
create policy "anyone can read compensation" on public.compensation for
select
	to authenticated using (true);

-- Venue admins can update compensation for their venue.
create policy "venue admins can update compensation" on public.compensation
for update
	to authenticated using (
		public.isAdmin (
			(
				select
					venueid
				from
					roles
				where
					roles.id=compensation.role
			)
		)
	)
with
	check (true);

-- Venue admins can delete compensation for their venue.
create policy "venue admins can delete compensation" on public.compensation for DELETE to authenticated using (
	public.isAdmin (
		(
			select
				venueid
			from
				roles
			where
				roles.id=compensation.role
		)
	)
);

alter publication supabase_realtime
add table compensation;
