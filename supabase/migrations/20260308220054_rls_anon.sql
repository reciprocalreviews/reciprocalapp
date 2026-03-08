drop policy "admins, approvers and volunteers can create assignments" on "public"."assignments";

drop policy "assignees and approvers can update assignments" on "public"."assignments";

drop policy "anyone can read compensation" on "public"."compensation";

drop policy "admins and volunteers can create conflicts" on "public"."conflicts";

drop policy "anyone can create currencies" on "public"."currencies";

drop policy "minters can delete currencies" on "public"."currencies";

drop policy "minters can update currencies" on "public"."currencies";

drop policy "emails can't be edited" on "public"."emails";

drop policy "recipients and venue admins can see the emails sent" on "public"."emails";

drop policy "only minters can create exchanges" on "public"."exchanges";

drop policy "only minters can delete exchanges" on "public"."exchanges";

drop policy "only minters can update exchanges" on "public"."exchanges";

drop policy "only admins can create venue roles" on "public"."roles";

drop policy "only admins can delete roles" on "public"."roles";

drop policy "only admins can update roles" on "public"."roles";

drop policy "Scholars can be edited by stewards and selves" on "public"."scholars";

drop policy "Scholars can remove themselves" on "public"."scholars";

drop policy "Scholars cannot be inserted except by platform" on "public"."scholars";

drop policy "anyone can read submission types" on "public"."submission_types";

drop policy "authors, assigned, and bidders can view submissions" on "public"."submissions";

drop policy "admins can update proposals" on "public"."supporters";

drop policy "supporters can stop supporting" on "public"."supporters";

drop policy "only minters can create tokens" on "public"."tokens";

drop policy "tokens cannot be deleted" on "public"."tokens";

drop policy "only owners can transfer their tokens if approved" on "public"."transactions";

drop policy "only the giver and minters can update transactions" on "public"."transactions";

drop policy "transactions are only visible to minters and those involved" on "public"."transactions";

drop policy "transactions cannot be deleted" on "public"."transactions";

drop policy "only stewards can create venues" on "public"."venues";

drop policy "stewards and admins can delete venues" on "public"."venues";

drop policy "stewards and admins can update venues" on "public"."venues";

drop policy "admins and volunteers can delete" on "public"."volunteers";

drop policy "admins can invite and volunteers if not invite only" on "public"."volunteers";

drop policy "volunteers can update" on "public"."volunteers";

create policy "admins, approvers and volunteers can create assignments" on "public"."assignments" as permissive for insert to authenticated
with
	check (
		(
			public.isadmin (venue)
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

create policy "assignees and approvers can update assignments" on "public"."assignments" as permissive
for update
	to authenticated using (
		(
			(
				scholar=(
					select
						auth.uid () as uid
				)
			)
			or public.isapprover (role)
		)
	);

create policy "anyone can read compensation" on "public"."compensation" as permissive for
select
	to anon,
	authenticated using (true);

create policy "admins and volunteers can create conflicts" on "public"."conflicts" as permissive for insert to authenticated
with
	check (
		(
			public.isadmin (
				(
					select
						submissions.venue
					from
						public.submissions
					where
						(submissions.id=conflicts.submissionid)
				)
			)
			or (
				exists (
					select
						volunteers.id,
						volunteers.scholarid,
						volunteers.roleid,
						volunteers.created_at,
						volunteers.expertise,
						volunteers.active,
						volunteers.accepted
					from
						public.volunteers
					where
						(
							(volunteers.scholarid=conflicts.scholarid)
							and (
								volunteers.roleid in (
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
			)
		)
	);

create policy "anyone can create currencies" on "public"."currencies" as permissive for insert to authenticated
with
	check (public.issteward ());

create policy "minters can delete currencies" on "public"."currencies" as permissive for delete to authenticated using (
	(
		(
			select
				auth.uid () as uid
		)=any (minters)
	)
);

create policy "minters can update currencies" on "public"."currencies" as permissive
for update
	to authenticated using (
		(
			(
				select
					auth.uid () as uid
			)=any (minters)
		)
	);

create policy "emails can't be edited" on "public"."emails" as permissive
for update
	to authenticated using (false);

create policy "recipients and venue admins can see the emails sent" on "public"."emails" as permissive for
select
	to authenticated using (
		(
			(
				(
					select
						auth.uid () as uid
				)=scholar
			)
			or (
				(venue is not null)
				and public.isadmin (venue)
			)
		)
	);

create policy "only minters can create exchanges" on "public"."exchanges" as permissive for insert to authenticated
with
	check (
		(
			public.isminter (
				(
					select
						auth.uid () as uid
				),
				currency_from
			)
			or public.isminter (
				(
					select
						auth.uid () as uid
				),
				currency_to
			)
		)
	);

create policy "only minters can delete exchanges" on "public"."exchanges" as permissive for delete to authenticated using (
	(
		public.isminter (
			(
				select
					auth.uid () as uid
			),
			currency_from
		)
		or public.isminter (
			(
				select
					auth.uid () as uid
			),
			currency_to
		)
	)
);

create policy "only minters can update exchanges" on "public"."exchanges" as permissive
for update
	to authenticated using (
		(
			public.isminter (
				(
					select
						auth.uid () as uid
				),
				currency_from
			)
			or public.isminter (
				(
					select
						auth.uid () as uid
				),
				currency_to
			)
		)
	);

create policy "only admins can create venue roles" on "public"."roles" as permissive for insert to authenticated
with
	check (public.isadmin (venueid));

create policy "only admins can delete roles" on "public"."roles" as permissive for delete to authenticated using (public.isadmin (venueid));

create policy "only admins can update roles" on "public"."roles" as permissive
for update
	to authenticated using (public.isadmin (venueid));

create policy "Scholars can be edited by stewards and selves" on "public"."scholars" as permissive
for update
	to authenticated using (
		(
			(
				id=(
					select
						auth.uid () as uid
				)
			)
			or public.issteward ()
		)
	);

create policy "Scholars can remove themselves" on "public"."scholars" as permissive for delete to authenticated using (
	(
		id=(
			select
				auth.uid () as uid
		)
	)
);

create policy "Scholars cannot be inserted except by platform" on "public"."scholars" as permissive for insert to authenticated
with
	check (false);

create policy "anyone can read submission types" on "public"."submission_types" as permissive for
select
	to anon,
	authenticated using (true);

create policy "authors, assigned, and bidders can view submissions" on "public"."submissions" as permissive for
select
	to authenticated using (
		(
			(
				(
					select
						auth.uid () as uid
				)=any (authors)
			)
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
											(
												(roles.venueid=submissions.venue)
												and (roles.biddable=true)
											)
									)
								)
							)
						)
				)
			)
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

create policy "admins can update proposals" on "public"."supporters" as permissive
for update
	to authenticated using (
		(
			(
				select
					auth.uid () as uid
			)=scholarid
		)
	);

create policy "supporters can stop supporting" on "public"."supporters" as permissive for delete to authenticated using (
	(
		(
			select
				auth.uid () as uid
		)=scholarid
	)
);

create policy "only minters can create tokens" on "public"."tokens" as permissive for insert to authenticated
with
	check (
		(
			(
				select
					auth.uid () as uid
			)=any (
				(
					select
						currencies.minters
					from
						public.currencies
					where
						(currencies.id=tokens.currency)
				)::uuid[]
			)
		)
	);

create policy "tokens cannot be deleted" on "public"."tokens" as permissive for delete to authenticated using (false);

create policy "only owners can transfer their tokens if approved" on "public"."transactions" as permissive for insert to authenticated
with
	check (
		(
			(status='proposed'::public.transaction_status)
			or (
				(status='approved'::public.transaction_status)
				and (
					(
						(from_scholar is not null)
						and (
							(
								select
									auth.uid () as uid
							)=from_scholar
						)
					)
					or (
						(from_venue is not null)
						and (
							(
								select
									auth.uid () as uid
							)=any (
								(
									select
										venues.admins
									from
										public.venues
									where
										(venues.id=transactions.from_venue)
								)::uuid[]
							)
						)
					)
					or (
						(from_scholar is null)
						and (from_venue is null)
					)
				)
			)
		)
	);

create policy "only the giver and minters can update transactions" on "public"."transactions" as permissive
for update
	to authenticated using (
		(
			(
				(
					select
						auth.uid () as uid
				)=from_scholar
			)
			or (
				(
					select
						auth.uid () as uid
				)=any (
					(
						select
							currencies.minters
						from
							public.currencies
						where
							(currencies.id=transactions.currency)
					)::uuid[]
				)
			)
			or (
				(from_venue is not null)
				and (
					(
						select
							auth.uid () as uid
					)=any (
						(
							select
								venues.admins
							from
								public.venues
							where
								(venues.id=transactions.from_venue)
						)::uuid[]
					)
				)
			)
		)
	);

create policy "transactions are only visible to minters and those involved" on "public"."transactions" as permissive for
select
	to authenticated using (
		(
			(
				(
					select
						auth.uid () as uid
				)=from_scholar
			)
			or (
				(
					select
						auth.uid () as uid
				)=to_scholar
			)
			or (
				(
					select
						auth.uid () as uid
				)=any (
					(
						select
							currencies.minters
						from
							public.currencies
						where
							(currencies.id=transactions.currency)
					)::uuid[]
				)
			)
			or (
				(from_venue is not null)
				and (
					(
						select
							auth.uid () as uid
					)=any (
						(
							select
								venues.admins
							from
								public.venues
							where
								(venues.id=transactions.from_venue)
						)::uuid[]
					)
				)
			)
			or (
				(to_venue is not null)
				and (
					(
						select
							auth.uid () as uid
					)=any (
						(
							select
								venues.admins
							from
								public.venues
							where
								(venues.id=transactions.to_venue)
						)::uuid[]
					)
				)
			)
		)
	);

create policy "transactions cannot be deleted" on "public"."transactions" as permissive for delete to authenticated using (
	(
		(
			select
				auth.uid () as uid
		)=any (
			(
				select
					currencies.minters
				from
					public.currencies
				where
					(currencies.id=transactions.currency)
			)::uuid[]
		)
	)
);

create policy "only stewards can create venues" on "public"."venues" as permissive for insert to authenticated
with
	check (public.issteward ());

create policy "stewards and admins can delete venues" on "public"."venues" as permissive for delete to authenticated using (
	(
		public.issteward ()
		or (
			(
				select
					auth.uid () as uid
			)=any (admins)
		)
	)
);

create policy "stewards and admins can update venues" on "public"."venues" as permissive
for update
	to authenticated using (
		(
			public.issteward ()
			or (
				(
					select
						auth.uid () as uid
				)=any (admins)
			)
		)
	);

create policy "admins and volunteers can delete" on "public"."volunteers" as permissive for delete to authenticated using (
	(
		public.isadmin (
			(
				select
					roles.venueid
				from
					public.roles
				where
					(roles.id=volunteers.roleid)
			)
		)
		or (
			(
				select
					auth.uid () as uid
			)=scholarid
		)
	)
);

create policy "admins can invite and volunteers if not invite only" on "public"."volunteers" as permissive for insert to authenticated
with
	check (
		(
			public.isadmin (
				(
					select
						roles.venueid
					from
						public.roles
					where
						(roles.id=volunteers.roleid)
				)
			)
			or (
				(
					(
						select
							auth.uid () as uid
					)=scholarid
				)
				and (
					not (
						select
							roles.invited
						from
							public.roles
						where
							(roles.id=volunteers.roleid)
					)
				)
			)
		)
	);

create policy "volunteers can update" on "public"."volunteers" as permissive
for update
	to authenticated using (
		(
			(
				select
					auth.uid () as uid
			)=scholarid
		)
	);
