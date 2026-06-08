--------------------------------------
-- Schema
create type public."transaction_status" as enum('proposed', 'approved', 'declined');

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
	-- The purpose of the transaction, containing any information necessary for
	-- approval of the transaction by the from source.
	purpose text not null,
	-- The status of the transaction
	status public.transaction_status not null,
	-- The scholar who declined the transaction (null when status != 'declined').
	decliner uuid,
	-- The reason the decliner gave when declining (null when status != 'declined').
	decline_reason text,
	-- Require that there is either a scholar or venue source but not both
	constraint check_from check ((num_nonnulls (from_scholar, from_venue)<=1)),
	-- Require that there is either a scholar or venue destination but not both
	constraint check_to check ((num_nonnulls (to_scholar, to_venue)=1))
);

alter table public.transactions OWNER to "postgres";

grant all on table public.transactions to "anon";

grant all on table public.transactions to "authenticated";

grant all on table public.transactions to "service_role";

-- A transaction is an immutable record of history. Only its status, the
-- accompanying decline fields, and `tokens` (the null-UUID placeholder until the
-- tokens are assigned on approval) may change after creation. `grant all` above
-- confers a TABLE-level UPDATE that a column-level revoke cannot subtract, so
-- remove the table-level UPDATE and re-grant only the mutable columns.
revoke
update on public.transactions
from
	authenticated;

grant
update (status, tokens, decliner, decline_reason) on public.transactions to authenticated;

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

alter table only public.transactions
add constraint transactions_decliner_fkey foreign KEY (decliner) references public.scholars (id);

--------------------------------------
-- Security
alter table public.transactions ENABLE row LEVEL SECURITY;

create policy "transactions are only visible to minters and those involved" on public.transactions for
select
	to authenticated using (
		(
			-- The transaction's creator
			(
				(
					select
						auth.uid () as uid
				)=creator
			)
			-- Scholars giving can see their transactions
			or (
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

create policy "only owners can transfer their tokens if approved" on public.transactions for INSERT to authenticated
with
	check (
		(
			-- Transactions can be proposed by anyone.
			(status='proposed'::transaction_status)
			or (
				(status='approved'::transaction_status)
				and (
					-- No-self-enrichment (DESIGN.md L388). Spending one's own
					-- balance is not enrichment — no recipient restriction.
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
					-- the approver must not be the recipient or a venue they
					-- admin, since that would be self-enrichment.
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

create policy "only the giver and minters can update transactions" on public.transactions
for update
	to authenticated using (
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
	)
with
	check (
		-- Post-update: the updater must still be a giver, minter, or from-venue admin.
		-- Mirrors the using clause so adding `with check` does not widen post-update behavior
		-- (Postgres would otherwise stop reusing using as the post-update check).
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
		-- No-self-enrichment (DESIGN.md L388). On approval: spending one's
		-- own balance (from_scholar = auth.uid()) imposes no recipient
		-- restriction; otherwise the approver must not be the recipient or
		-- a venue they admin (which would enrich them from someone else's
		-- tokens). Other status transitions (e.g. flipping to `declined`)
		-- are not restricted by this check.
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

create policy "transactions cannot be deleted" on public.transactions for DELETE to authenticated using (
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

--------------------------------------
-- RPCs (defined in migration 20260608000000_atomic_crud.sql)
-- transfer_tokens: move _amount tokens of _currency from one entity to another
-- and finalize an existing proposed transaction or record a new approved one,
-- atomically. SECURITY DEFINER, re-implementing the tokens UPDATE policy (owner
-- scholar, or venue admin / priority-0) and the transactions no-self-enrichment
-- rule. Entity ids are pre-resolved; kinds are 'venueid' or 'scholarid'.
create or replace function public.transfer_tokens (
	_currency uuid,
	_from uuid,
	_from_kind text,
	_to uuid,
	_to_kind text,
	_amount integer,
	_purpose text,
	_transaction uuid
) returns jsonb language plpgsql security definer
set
	search_path = public, pg_temp as $function$
declare
	_caller uuid;
	_from_scholar uuid;
	_from_venue uuid;
	_to_scholar uuid;
	_to_venue uuid;
	_token_ids uuid[];
	_txn_id uuid;
begin
	-- Identify and require an authenticated caller.
	_caller := (select auth.uid());
	if _caller is null then
		raise exception 'Authentication required';
	end if;
	-- A transfer must move a positive number of tokens.
	if _amount is null or _amount <= 0 then
		raise exception 'Transfer amount must be positive';
	end if;

	-- Sort the pre-resolved from/to ids into the scholar vs venue slots.
	if _from_kind = 'venueid' then _from_venue := _from; else _from_scholar := _from; end if;
	if _to_kind = 'venueid' then _to_venue := _to; else _to_scholar := _to; end if;

	-- Authorize the move and forbid self-enrichment.
	if _from_scholar is not null then
		-- Spending one's own balance: only the owner may, and there is no
		-- restriction on who receives it.
		if _caller <> _from_scholar then
			raise exception 'You can only transfer your own tokens';
		end if;
	else
		-- Moving a venue's tokens: only its admins or a priority-0 role holder may.
		if not (public.isAdmin(_from_venue) or public.isPriorityZero(_from_venue)) then
			raise exception 'You are not authorized to transfer this venue''s tokens';
		end if;
		-- And the mover must not be the recipient (or an admin of a recipient
		-- venue) — that would be paying themselves from the reserve.
		if _to_scholar is not null and _to_scholar = _caller then
			raise exception 'You cannot transfer tokens to yourself';
		end if;
		if _to_venue is not null and public.isAdmin(_to_venue) then
			raise exception 'You cannot transfer tokens to a venue you administer';
		end if;
	end if;

	-- Pick exactly _amount tokens currently owned by the source in this currency.
	select array_agg(id) into _token_ids
	from (
		select id from public.tokens
		where currency = _currency
		  and (
			(_from_scholar is not null and scholar = _from_scholar)
			or (_from_venue is not null and venue = _from_venue)
		  )
		order by id
		limit _amount
	) sub;

	-- The source must actually hold that many tokens. RR003 lets the app show
	-- the specific "insufficient tokens" message (see SupabaseCRUD.rpcErrorKey).
	if _token_ids is null or cardinality(_token_ids) < _amount then
		raise exception 'Insufficient tokens to transfer' using errcode = 'RR003';
	end if;

	-- Reassign all chosen tokens to the destination in one statement.
	update public.tokens set scholar = _to_scholar, venue = _to_venue where id = any(_token_ids);

	if _transaction is not null then
		-- Finalizing a previously proposed transfer: flip it to approved and
		-- record which tokens actually moved.
		update public.transactions set status = 'approved', tokens = _token_ids where id = _transaction;
		_txn_id := _transaction;
	else
		-- A fresh transfer (e.g. a gift): record a new approved transaction.
		insert into public.transactions (
			creator, from_scholar, from_venue, to_scholar, to_venue,
			tokens, currency, purpose, status
		) values (
			_caller, _from_scholar, _from_venue, _to_scholar, _to_venue,
			_token_ids, _currency, _purpose, 'approved'
		) returning id into _txn_id;
	end if;

	-- Return the transaction id and the tokens that moved.
	return jsonb_build_object('transaction_id', _txn_id, 'token_ids', to_jsonb(_token_ids));
end;
$function$;

revoke execute on function public.transfer_tokens (uuid, uuid, text, uuid, text, integer, text, uuid) from public;
grant execute on function public.transfer_tokens (uuid, uuid, text, uuid, text, integer, text, uuid) to authenticated;

-- approve_transaction: approve a proposed transaction, minting and/or moving
-- tokens and flipping status to 'approved', atomically. SECURITY DEFINER,
-- re-implementing the transactions UPDATE policy (giver scholar, venue admin, or
-- minter), the no-self-enrichment rule, and the tokens INSERT policy (minting
-- requires a minter). Three branches: pure mint; scholar transfer; venue
-- transfer (minting placeholder tokens first when the reserve lacks them).
create or replace function public.approve_transaction (
	_transaction_id uuid
) returns jsonb language plpgsql security definer
set
	search_path = public, pg_temp as $function$
declare
	_caller uuid;
	_txn public.transactions;
	_from uuid;
	_to uuid;
	_spending_own boolean;
	_null_count integer;
	_needed integer;
	_token_ids uuid[];
begin
	-- Identify and require an authenticated caller.
	_caller := (select auth.uid());
	if _caller is null then
		raise exception 'Authentication required';
	end if;

	-- Load the transaction; it must exist and still be awaiting approval.
	select * into _txn from public.transactions where id = _transaction_id;
	if not found then
		raise exception 'Transaction not found';
	end if;
	-- RR001 lets the app show the specific "already approved" message.
	if _txn.status <> 'proposed' then
		raise exception 'Transaction is not proposed' using errcode = 'RR001';
	end if;

	-- Collapse the from/to scholar-or-venue pairs into single endpoints; every
	-- transaction has a recipient.
	_from := coalesce(_txn.from_scholar, _txn.from_venue);
	_to := coalesce(_txn.to_scholar, _txn.to_venue);
	if _to is null then
		raise exception 'Transaction has no recipient';
	end if;

	-- No-self-enrichment: spending one's own balance is unrestricted; otherwise
	-- the approver may not be the recipient or an admin of the recipient venue.
	-- RR002 lets the app show the specific self-dealing message.
	_spending_own := (_txn.from_scholar is not null and _txn.from_scholar = _caller);
	if not _spending_own then
		if _txn.to_scholar is not null and _txn.to_scholar = _caller then
			raise exception 'You cannot approve a transaction that pays you' using errcode = 'RR002';
		end if;
		if _txn.to_venue is not null and public.isAdmin(_txn.to_venue) then
			raise exception 'You cannot approve a transaction that pays a venue you administer' using errcode = 'RR002';
		end if;
	end if;

	-- How many of the listed tokens are placeholders (not yet real tokens)?
	_null_count := (
		select count(*) from unnest(_txn.tokens) t
		where t = '00000000-0000-0000-0000-000000000000'::uuid
	);

	-- Branch A: pure mint — no source, all placeholders, a venue recipient.
	if _from is null then
		if _txn.to_venue is null then
			raise exception 'A mint transaction must target a venue';
		end if;
		if _null_count = 0 or _null_count <> cardinality(_txn.tokens) then
			raise exception 'A mint transaction must contain only placeholder tokens';
		end if;
		-- Only a minter may bring new tokens into existence.
		if not public.isminter(_caller, _txn.currency) then
			raise exception 'Only currency minters can approve a mint';
		end if;
		-- Mint the tokens straight into the recipient venue and capture their ids.
		with inserted as (
			insert into public.tokens (currency, venue, scholar)
			select _txn.currency, _txn.to_venue, null from generate_series(1, _null_count)
			returning id
		)
		select array_agg(id) into _token_ids from inserted;

		-- Finalize the transaction with the real token ids.
		update public.transactions set status = 'approved', tokens = _token_ids where id = _transaction_id;
		return jsonb_build_object('transaction_id', _transaction_id, 'token_ids', to_jsonb(_token_ids));
	end if;

	-- Branch B: transfer. Authorize moving the source's tokens.
	if _txn.from_scholar is not null then
		-- A scholar's own balance: only that scholar may approve the spend.
		if _caller <> _txn.from_scholar then
			raise exception 'You can only approve transfers of your own tokens';
		end if;
	else
		-- A venue's reserve: a venue admin or a currency minter may approve
		-- (mirrors the transactions UPDATE policy).
		if not (public.isAdmin(_txn.from_venue) or public.isminter(_caller, _txn.currency)) then
			raise exception 'You are not authorized to approve this transaction';
		end if;
	end if;

	-- If the venue source is short real tokens, mint the placeholders into its
	-- reserve first. Minting requires a minter (tokens INSERT policy).
	if _null_count > 0 and _txn.from_venue is not null then
		if not public.isminter(_caller, _txn.currency) then
			raise exception 'Only currency minters can mint the tokens this transaction requires';
		end if;
		insert into public.tokens (currency, venue, scholar)
		select _txn.currency, _txn.from_venue, null from generate_series(1, _null_count);
	end if;

	-- Choose as many of the source's tokens as the transaction calls for.
	_needed := cardinality(_txn.tokens);
	select array_agg(id) into _token_ids
	from (
		select id from public.tokens
		where currency = _txn.currency
		  and (
			(_txn.from_scholar is not null and scholar = _txn.from_scholar)
			or (_txn.from_venue is not null and venue = _txn.from_venue)
		  )
		order by id
		limit _needed
	) sub;

	-- Bail (rolling back any mint above) if the source can't cover the transfer.
	if _token_ids is null or cardinality(_token_ids) < _needed then
		raise exception 'Insufficient tokens to complete the transfer' using errcode = 'RR003';
	end if;

	-- Move the tokens to the recipient and finalize the transaction together.
	update public.tokens set scholar = _txn.to_scholar, venue = _txn.to_venue where id = any(_token_ids);
	update public.transactions set status = 'approved', tokens = _token_ids where id = _transaction_id;

	return jsonb_build_object('transaction_id', _transaction_id, 'token_ids', to_jsonb(_token_ids));
end;
$function$;

revoke execute on function public.approve_transaction (uuid) from public;
grant execute on function public.approve_transaction (uuid) to authenticated;

alter publication supabase_realtime
add table transactions;
