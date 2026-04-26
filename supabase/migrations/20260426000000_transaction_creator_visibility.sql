drop policy "transactions are only visible to minters and those involved" on "public"."transactions";

create policy "transactions are only visible to minters and those involved" on "public"."transactions" as permissive for
select
	to authenticated using (
		(
			(
				(
					select
						auth.uid () as uid
				)=creator
			)
			or (
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
