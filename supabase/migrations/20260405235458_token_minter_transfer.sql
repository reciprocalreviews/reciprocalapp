drop policy "only token owners and venue admins can update a token" on public.tokens;

create policy "only token owners, venue admins, and minters can update a token" on public.tokens
for update
	to authenticated using (
		(
			(
				(venue is not null)
				and public.isAdmin (venue)
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
							(currencies.id=tokens.currency)
					)::uuid[]
				)
			)
		)
	)
with
	check (true);
