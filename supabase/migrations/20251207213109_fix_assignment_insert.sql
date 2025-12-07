drop policy "editors and volunteers can create assignments" on "public"."assignments";

create policy "editors and volunteers can create assignments" on "public"."assignments" as permissive for insert to authenticated,
anon
with
	check (
		(
			public.iseditor (venue)
			or (
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
	);
