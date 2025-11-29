drop policy "editors can create submissions" on "public"."submissions";

drop policy "editors and volunteers can create assignments" on "public"."assignments";

drop policy "editors, assignees, and approvers can see assignments" on "public"."assignments";

drop policy "editors, assignees, and approvers can update assignments" on "public"."assignments";

drop policy "anyone can create currencies" on "public"."currencies";

drop policy "anyone can view currencies" on "public"."currencies";

drop policy "minters can delete currencies" on "public"."currencies";

drop policy "minters can update currencies" on "public"."currencies";

drop policy "emails can't be edited" on "public"."emails";

drop policy "scholars and venue editors can see the emails sent" on "public"."emails";

drop policy "anyone can view exchanges" on "public"."exchanges";

drop policy "only minters can create exchanges" on "public"."exchanges";

drop policy "only minters can delete exchanges" on "public"."exchanges";

drop policy "only minters can update exchanges" on "public"."exchanges";

drop policy "admins can delete proposals" on "public"."proposals";

drop policy "admins can update proposals" on "public"."proposals";

drop policy "anyone can propose venues" on "public"."proposals";

drop policy "anyone can view proposals" on "public"."proposals";

drop policy "anyone can view roles" on "public"."roles";

drop policy "only editors can create venue roles" on "public"."roles";

drop policy "only editors can delete roles" on "public"."roles";

drop policy "only editors can update roles" on "public"."roles";

drop policy "Scholar can insert themselves" on "public"."scholars";

drop policy "Scholar metadata is public" on "public"."scholars";

drop policy "Scholars can be edited by stewards and selves" on "public"."scholars";

drop policy "Scholars can remove themselves" on "public"."scholars";

drop policy "authors, editors, and bidders can view submissions" on "public"."submissions";

drop policy "admins can update proposals" on "public"."supporters";

drop policy "anyone can support proposals" on "public"."supporters";

drop policy "anyone can view supporters" on "public"."supporters";

drop policy "supporters can stop supporting" on "public"."supporters";

drop policy "only minters can create tokens" on "public"."tokens";

drop policy "only token owners can update a token" on "public"."tokens";

drop policy "tokens are public" on "public"."tokens";

drop policy "tokens cannot be deleted" on "public"."tokens";

drop policy "only owners can transfer their tokens if approved" on "public"."transactions";

drop policy "only the giver and minters can update transactions" on "public"."transactions";

drop policy "transactions are only visible to minters and those involved" on "public"."transactions";

drop policy "transactions cannot be deleted" on "public"."transactions";

drop policy "anyone can view venues" on "public"."venues";

drop policy "only stewards can create venues" on "public"."venues";

drop policy "stewards and editors can delete venues" on "public"."venues";

drop policy "stewards and editors can update venues" on "public"."venues";

drop policy "anyone can view volunteers" on "public"."volunteers";

drop policy "editors and volunteers can delete" on "public"."volunteers";

drop policy "editors can invite and volunteers if not invite only" on "public"."volunteers";

drop policy "volunteers can update" on "public"."volunteers";

create policy "anyone can create submissions" on "public"."submissions" as permissive for insert to authenticated
with
	check (true);

create policy "editors and volunteers can create assignments" on "public"."assignments" as permissive for insert to authenticated,
anon
with
	check (
		(
			public.iseditor (venue)
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
								and (volunteers.accepted=volunteers.accepted)
							)
					)
				)
			)
		)
	);

create policy "editors, assignees, and approvers can see assignments" on "public"."assignments" as permissive for
select
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
	)
with
	check (true);

create policy "anyone can create currencies" on "public"."currencies" as permissive for insert to authenticated,
anon
with
	check (true);

create policy "anyone can view currencies" on "public"."currencies" as permissive for
select
	to authenticated,
	anon using (true);

create policy "minters can delete currencies" on "public"."currencies" as permissive for delete to authenticated,
anon using (
	(
		(
			select
				auth.uid () as uid
		)=any (minters)
	)
);

create policy "minters can update currencies" on "public"."currencies" as permissive
for update
	to authenticated,
	anon using (
		(
			(
				select
					auth.uid () as uid
			)=any (minters)
		)
	);

create policy "emails can't be edited" on "public"."emails" as permissive
for update
	to authenticated,
	anon using (false);

create policy "scholars and venue editors can see the emails sent" on "public"."emails" as permissive for
select
	to authenticated,
	anon using (
		(
			(
				(
					select
						auth.uid () as uid
				)=scholar
			)
			or (
				(venue is not null)
				and public.iseditor (venue)
			)
		)
	);

create policy "anyone can view exchanges" on "public"."exchanges" as permissive for
select
	to authenticated,
	anon using (true);

create policy "only minters can create exchanges" on "public"."exchanges" as permissive for insert to authenticated,
anon
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

create policy "only minters can delete exchanges" on "public"."exchanges" as permissive for delete to authenticated,
anon using (
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
	to authenticated,
	anon using (
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

create policy "admins can delete proposals" on "public"."proposals" as permissive for delete to authenticated,
anon using (public.issteward ());

create policy "admins can update proposals" on "public"."proposals" as permissive
for update
	to authenticated,
	anon using (public.issteward ());

create policy "anyone can propose venues" on "public"."proposals" as permissive for insert to authenticated,
anon
with
	check (true);

create policy "anyone can view proposals" on "public"."proposals" as permissive for
select
	to authenticated,
	anon using (true);

create policy "anyone can view roles" on "public"."roles" as permissive for
select
	to authenticated,
	anon using (true);

create policy "only editors can create venue roles" on "public"."roles" as permissive for insert to authenticated,
anon
with
	check (public.iseditor (venueid));

create policy "only editors can delete roles" on "public"."roles" as permissive for delete to authenticated,
anon using (public.iseditor (venueid));

create policy "only editors can update roles" on "public"."roles" as permissive
for update
	to authenticated,
	anon using (public.iseditor (venueid));

create policy "Scholar can insert themselves" on "public"."scholars" as permissive for insert to authenticated,
anon
with
	check (true);

create policy "Scholar metadata is public" on "public"."scholars" as permissive for
select
	to authenticated,
	anon using (true);

create policy "Scholars can be edited by stewards and selves" on "public"."scholars" as permissive
for update
	to authenticated,
	anon using (
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

create policy "Scholars can remove themselves" on "public"."scholars" as permissive for delete to authenticated,
anon using (
	(
		id=(
			select
				auth.uid () as uid
		)
	)
);

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
											(submissions.venue=submissions.venue)
									)
								)
							)
						)
				)
			)
		)
	);

create policy "admins can update proposals" on "public"."supporters" as permissive
for update
	to authenticated,
	anon using (
		(
			(
				select
					auth.uid () as uid
			)=scholarid
		)
	);

create policy "anyone can support proposals" on "public"."supporters" as permissive for insert to authenticated,
anon
with
	check (true);

create policy "anyone can view supporters" on "public"."supporters" as permissive for
select
	to authenticated,
	anon using (true);

create policy "supporters can stop supporting" on "public"."supporters" as permissive for delete to authenticated,
anon using (
	(
		(
			select
				auth.uid () as uid
		)=scholarid
	)
);

create policy "only minters can create tokens" on "public"."tokens" as permissive for insert to authenticated,
anon
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

create policy "only token owners can update a token" on "public"."tokens" as permissive
for update
	to authenticated,
	anon using (
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

create policy "tokens are public" on "public"."tokens" as permissive for
select
	to authenticated,
	anon using (true);

create policy "tokens cannot be deleted" on "public"."tokens" as permissive for delete to authenticated,
anon using (false);

create policy "only owners can transfer their tokens if approved" on "public"."transactions" as permissive for insert to authenticated,
anon
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
										venues.editors
									from
										public.venues
									where
										(venues.id=transactions.from_venue)
								)::uuid[]
							)
						)
					)
				)
			)
		)
	);

create policy "only the giver and minters can update transactions" on "public"."transactions" as permissive
for update
	to authenticated,
	anon using (
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
								venues.editors
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
	to authenticated,
	anon using (
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
								venues.editors
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
								venues.editors
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

create policy "transactions cannot be deleted" on "public"."transactions" as permissive for delete to authenticated,
anon using (
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

create policy "anyone can view venues" on "public"."venues" as permissive for
select
	to authenticated,
	anon using (true);

create policy "only stewards can create venues" on "public"."venues" as permissive for insert to authenticated,
anon
with
	check (public.issteward ());

create policy "stewards and editors can delete venues" on "public"."venues" as permissive for delete to authenticated,
anon using (
	(
		public.issteward ()
		or (
			(
				select
					auth.uid () as uid
			)=any (editors)
		)
	)
);

create policy "stewards and editors can update venues" on "public"."venues" as permissive
for update
	to authenticated,
	anon using (
		(
			public.issteward ()
			or (
				(
					select
						auth.uid () as uid
				)=any (editors)
			)
		)
	);

create policy "anyone can view volunteers" on "public"."volunteers" as permissive for
select
	to authenticated,
	anon using (true);

create policy "editors and volunteers can delete" on "public"."volunteers" as permissive for delete to authenticated,
anon using (
	(
		public.iseditor (
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

create policy "editors can invite and volunteers if not invite only" on "public"."volunteers" as permissive for insert to authenticated,
anon
with
	check (
		(
			public.iseditor (
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
	to authenticated,
	anon using (
		(
			(
				select
					auth.uid () as uid
			)=scholarid
		)
	);
