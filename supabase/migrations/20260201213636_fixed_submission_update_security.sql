drop policy "authors and editors can update submissions" on "public"."submissions";

create policy "authors and editors can update submissions" on "public"."submissions" as permissive
for update
	to authenticated using (
		(
			(
				exists (
					select
						assignments.id
					from
						public.assignments
					where
						(
							(assignments.submission=submissions.id)
							and (
								assignments.scholar=(
									select
										auth.uid () as uid
								)
							)
							and (assignments.approved=true)
							and (
								exists (
									select
										roles.id
									from
										public.roles
									where
										(
											(roles.id=assignments.role)
											and (roles.priority=0)
										)
								)
							)
						)
				)
			)
			or (
				(
					select
						auth.uid () as uid
				)=any (authors)
			)
		)
	);
