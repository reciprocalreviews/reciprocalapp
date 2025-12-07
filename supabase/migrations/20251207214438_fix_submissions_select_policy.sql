create policy "authors, editors, and bidders can view submissions" on "public"."submissions" as permissive for
select
	to authenticated,
	anon using (
		(
			(
				(
					select
						auth.uid () as uid
				)=any (authors)
			)
			or public.iseditor (venue)
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
									)
								)
							)
						)
				)
			)
		)
	);
