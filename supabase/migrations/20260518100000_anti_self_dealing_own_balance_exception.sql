-- DESIGN.md L388: the no-self-enrichment principle. An approver cannot
-- approve a transaction that enriches them — that is, one that moves
-- tokens the approver does not own (venue reserve, mint, or another
-- scholar's balance) to themselves or to a venue they administer.
-- Spending one's own balance is permitted regardless of recipient: it
-- isn't enrichment, it's the scholar exercising authority over their
-- own tokens. The previous policies blocked the latter too, conflating
-- "approver is the recipient" with "approver is being enriched".

drop policy "only owners can transfer their tokens if approved" on public.transactions;

create policy "only owners can transfer their tokens if approved" on public.transactions for INSERT to authenticated
with
	check (
		(
			-- Transactions can be proposed by anyone.
			(status='proposed'::transaction_status)
			or (
				(status='approved'::transaction_status)
				and (
					-- Spending one's own balance is not self-enrichment, so
					-- no recipient restriction applies.
					(
						(from_scholar is not null)
						and (
							(
								select
									auth.uid () as uid
							)=from_scholar
						)
					)
					-- Moving someone else's tokens (venue reserve or mint):
					-- the no-self-enrichment principle restricts the recipient.
					or (
						(
							(
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
			)
		)
	);

drop policy "only the giver and minters can update transactions" on public.transactions;

create policy "only the giver and minters can update transactions" on public.transactions
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
		-- Updater must still be a giver, minter, or from-venue admin
		-- (mirrors the using clause).
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
		-- No-self-enrichment on approval. Spending one's own balance
		-- (from_scholar = auth.uid()) is not enrichment, so no recipient
		-- restriction. When the approver is moving someone else's tokens
		-- (venue admin spending venue reserve, minter approving a mint),
		-- the recipient must not be the approver or a venue they admin.
		and (
			status<>'approved'::transaction_status
			or (
				(from_scholar is not null)
				and (
					(
						select
							auth.uid () as uid
					)=from_scholar
				)
			)
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
