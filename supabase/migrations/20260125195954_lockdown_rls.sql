drop policy "editors and volunteers can create assignments" on "public"."assignments";

drop policy "Scholar can insert themselves" on "public"."scholars";

drop policy "editors, assignees, and approvers can update assignments" on "public"."assignments";

drop policy "anyone can create currencies" on "public"."currencies";

drop policy "admins can delete proposals" on "public"."proposals";

drop policy "admins can update proposals" on "public"."proposals";

drop policy "anyone can propose venues" on "public"."proposals";

drop policy "editors can update submissions" on "public"."submissions";

drop policy "anyone can support proposals" on "public"."supporters";

drop policy "only token owners can update a token" on "public"."tokens";

create policy "editors, approvers, and volunteers can create assignments" on "public"."assignments" as permissive for insert to authenticated,
anon
with
	check (
		(
			public.iseditor (venue)
			or (
				public.isapprover (role)
				and public.isassigned (submission)
			)
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
											auth.uid () as uid
									)
								)
								and volunteers.active
								and (volunteers.accepted='accepted'::public.invited)
							)
					)
				)
			)
		)
	);

create policy "Scholars cannot be inserted except by platform" on "public"."scholars" as permissive for insert to authenticated,
anon
with
	check (false);

create policy "editors, assignees, and approvers can update assignments" on "public"."assignments" as permissive
for update
	to authenticated,
	anon using (
		(
			public.iseditor (venue)
			or (
				scholar=(
					select
						auth.uid () as uid
				)
			)
			or public.isapprover (role)
		)
	);

create policy "anyone can create currencies" on "public"."currencies" as permissive for insert to authenticated,
anon
with
	check (public.issteward ());

create policy "admins can delete proposals" on "public"."proposals" as permissive for delete to authenticated using (public.issteward ());

create policy "admins can update proposals" on "public"."proposals" as permissive
for update
	to authenticated using (public.issteward ());

create policy "anyone can propose venues" on "public"."proposals" as permissive for insert to authenticated
with
	check (true);

create policy "editors can update submissions" on "public"."submissions" as permissive
for update
	to authenticated using (public.iseditor (venue));

create policy "anyone can support proposals" on "public"."supporters" as permissive for insert to authenticated
with
	check (true);

create policy "only token owners can update a token" on "public"."tokens" as permissive
for update
	to authenticated using (
		(
			(
				(venue is not null)
				and public.iseditor (venue)
			)
			or (
				(scholar is not null)
				and (
					(
						select
							auth.uid () as uid
					)=scholar
				)
			)
		)
	)
with
	check (true);
