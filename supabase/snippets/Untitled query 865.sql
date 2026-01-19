drop policy "authors, editors, and bidders can view submissions" on "public"."submissions";

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