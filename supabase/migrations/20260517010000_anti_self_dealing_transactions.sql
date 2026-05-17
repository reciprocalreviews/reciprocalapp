-- Enforce DESIGN.md L388 anti-self-dealing invariant on the transactions table.
-- The approver (or inserter of an already-approved row) must not be the recipient:
-- not to_scholar, and not an admin of to_venue. Giver-side spending authority is
-- unchanged. Applied to both INSERT (covers the venue-admin gift path that bypasses
-- the propose-then-approve flow) and UPDATE (covers the standard minter approval).

drop policy "only owners can transfer their tokens if approved" on "public"."transactions";

create policy "only owners can transfer their tokens if approved" on "public"."transactions" as permissive for INSERT to authenticated
with
	check (
		(
			(status='proposed'::transaction_status)
			or (
				(status='approved'::transaction_status)
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
										venues
									where
										(venues.id=transactions.from_venue)
								)::uuid[]
							)
						)
					)
					or (
						from_scholar is null
						and from_venue is null
					)
				)
				and (
					to_scholar is null
					or (
						select
							auth.uid () as uid
					)<>to_scholar
				)
				and (
					to_venue is null
					or not (
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
		)
	);

drop policy "only the giver and minters can update transactions" on "public"."transactions";

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
	)
with
	check (
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
		and (
			status<>'approved'::transaction_status
			or (
				(
					to_scholar is null
					or (
						select
							auth.uid () as uid
					)<>to_scholar
				)
				and (
					to_venue is null
					or not (
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
		)
	);
