--------------------------------------
-- Schema
create type public."transaction_status" as enum('proposed', 'approved', 'canceled');

alter type public."transaction_status" OWNER to "postgres";

-- A table of transactions, recording a history of token transfers
create table if not exists public.transactions (
	-- The unique ID of the transaction
	id uuid default gen_random_uuid() not null,
	-- When the transaction was created
	created_at timestamp with time zone default now() not null,
	-- The scholar who created the transaction
	creator uuid not null,
	-- The scholar is giving the tokens
	from_scholar uuid,
	-- The venue giving the tokens
	from_venue uuid,
	-- The scholar who received the tokens,
	to_scholar uuid,
	-- The venue that received the tokens,
	to_venue uuid,
	-- An array of token ids moved in the transaction. If the null UUID, then tokens haven't been determined yet.
	tokens uuid[] not null,
	-- The currency the amount is in
	currency uuid not null,
	-- The purpose of the transaction, containing any information necessary for approval of the transaction by the from source
	-- Can also be used to specify the reason for cancelation.
	purpose text not null,
	-- The status of the transaction
	status public.transaction_status not null,
	-- Require that there is either a scholar or venue source but not both
	constraint check_from check ((num_nonnulls (from_scholar, from_venue)=1)),
	-- Require that there is either a scholar or venue destination but not both
	constraint check_to check ((num_nonnulls (to_scholar, to_venue)=1))
);

alter table public.transactions OWNER to "postgres";

grant all on table public.transactions to "anon";

grant all on table public.transactions to "authenticated";

grant all on table public.transactions to "service_role";

alter table only public.transactions
add constraint transactions_pkey primary key (id);

alter table only public.transactions
add constraint transactions_creator_fkey foreign KEY (creator) references public.scholars (id);

alter table only public.transactions
add constraint transactions_currency_fkey foreign KEY (currency) references public.currencies (id);

alter table only public.transactions
add constraint transactions_from_scholar_fkey foreign KEY (from_scholar) references public.scholars (id);

alter table only public.transactions
add constraint transactions_from_venue_fkey foreign KEY (from_venue) references public.venues (id);

alter table only public.transactions
add constraint transactions_to_scholar_fkey foreign KEY (to_scholar) references public.scholars (id);

alter table only public.transactions
add constraint transactions_to_venue_fkey foreign KEY (to_venue) references public.venues (id);

--------------------------------------
-- Security
alter table public.transactions ENABLE row LEVEL SECURITY;

create policy "transactions are only visible to minters and those involved" on public.transactions for
select
	to "authenticated",
	"anon" using (
		(
			-- Scholars giving can see their transactions
			(
				(
					select
						auth.uid () as uid
				)=from_scholar
			)
			-- Scholars receiving can see their transactions
			or (
				(
					select
						auth.uid () as uid
				)=to_scholar
			)
			-- Minters can see all transactions
			or (
				(
					select
						auth.uid () as uid
				)=any (
					(
						select
							currencies.minters
						from
							currencies
						where
							(currencies.id=transactions.currency)
					)::uuid[]
				)
			)
			-- Giving venue admins can see the venue's transactions given
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
			-- Receiving venues can see the venue's transactions received
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

create policy "only owners can transfer their tokens if approved" on public.transactions for INSERT to "authenticated",
"anon"
with
	check (
		(
			-- Transactions can be proposed by anyone
			(status='proposed'::transaction_status)
			or (
				-- Transactions can be approved by the giver
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
				)
			)
		)
	);

create policy "only the giver and minters can update transactions" on public.transactions
for update
	to "authenticated",
	"anon" using (
		(
			-- Givers can update their transactions
			(
				(
					select
						auth.uid () as uid
				)=from_scholar
			)
			-- Minters can update transactions
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
			-- Giving venue admins can update the venue's transactions given
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

create policy "transactions cannot be deleted" on public.transactions for DELETE to "authenticated",
"anon" using (
	(
		(
			select
				auth.uid () as uid
		)=any (
			(
				select
					currencies.minters
				from
					currencies
				where
					(currencies.id=transactions.currency)
			)::uuid[]
		)
	)
);

alter publication supabase_realtime
add table transactions;
