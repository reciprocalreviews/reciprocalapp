--------------------------------------
-- Schema
-- A table of minted tokens.
create table if not exists public.tokens (
	-- The unique ID of the token
	id uuid default gen_random_uuid() not null,
	-- The currency that the token is in
	currency uuid not null,
	-- The scholar that currently possess the token, or null, representing no one
	scholar uuid,
	-- The venue that currently posses the token, or null
	venue uuid,
	-- Require that there is either a scholar or venue owner, but not both
	constraint "check_owner" check ((num_nonnulls (scholar, venue)=1))
);

alter table public.tokens OWNER to "postgres";

alter table only public.tokens
add constraint tokens_pkey primary key (id);

alter table only public.tokens
add constraint tokens_currency_fkey foreign KEY (currency) references public.currencies (id);

alter table only public.tokens
add constraint tokens_scholar_fkey foreign KEY (scholar) references public.scholars (id);

alter table only public.tokens
add constraint tokens_venue_fkey foreign KEY (venue) references public.venues (id);

--------------------------------------
-- Indexes
create index tokens_currency_index on public.tokens using btree (currency);

create index tokens_scholar_index on public.tokens using btree (scholar);

create index tokens_venue_index on public.tokens using btree (venue);

--------------------------------------
-- Security
alter table public.tokens ENABLE row LEVEL SECURITY;

create policy "tokens are visible to authenticated scholars" on public.tokens for
select
	to authenticated using (true);

-- Tokens are never written directly by a client. Every mint and every transfer
-- goes through a SECURITY DEFINER RPC below (or in transactions.sql), each of
-- which re-implements the authorization it bypasses.
--
-- This used to be an INSERT policy for currency minters and an UPDATE policy for
-- the owning scholar / venue admins / priority-0 role holders. The UPDATE policy
-- was `with check (true)`, which pinned nothing about the resulting row: the
-- owning scholar could PATCH /rest/v1/tokens to reassign a token to anyone with
-- NO transactions row written, and could rewrite the token's `currency` to
-- counterfeit value in a currency they were never granted (balances are count(*)
-- of token rows). The write privilege is revoked below, and these deny policies
-- record the intent so policies_are() can assert it.
create policy "tokens are only created by definer rpcs" on public.tokens for INSERT to authenticated
with
	check (false);

create policy "tokens are only updated by definer rpcs" on public.tokens
for update
	to authenticated using (false);

create policy "tokens cannot be deleted" on public.tokens for DELETE to authenticated using (false);

--------------------------------------
-- RPCs (defined in migration 20260608000000_atomic_crud.sql)
-- mint_tokens: mint _amount tokens of _currency into a venue reserve and record
-- the approved mint transaction, atomically. SECURITY DEFINER, so it
-- re-implements the tokens INSERT policy (caller must be a minter) and the
-- transactions approved policy (a minter must not mint into a venue they admin).
create or replace function public.mint_tokens (
	_currency uuid,
	_amount integer,
	_to_venue uuid,
	_purpose text
) returns jsonb language plpgsql security definer
set
	search_path=public,
	pg_temp as $function$
declare
	_caller uuid;
	_token_ids uuid[];
	_txn_id uuid;
begin
	-- Identify and require an authenticated caller.
	_caller := (select auth.uid());
	if _caller is null then
		raise exception 'Authentication required';
	end if;
	-- A mint must create a positive number of tokens.
	if _amount is null or _amount <= 0 then
		raise exception 'Mint amount must be positive';
	end if;
	-- Only a minter of this currency may create its tokens (tokens INSERT policy).
	if not public.isminter(_caller, _currency) then
		raise exception 'Only currency minters can mint tokens';
	end if;
	-- Refuse self-enrichment: a minter must not mint into a venue they
	-- administer. The no_admin_minters trigger normally makes this impossible,
	-- but SECURITY DEFINER skips RLS, so we check explicitly.
	if public.isAdmin(_to_venue) then
		raise exception 'A minter cannot mint into a venue they administer';
	end if;

	-- Attribute the mint to the transaction it belongs to. The id is generated up
	-- front because the tokens are written before the transaction row exists, and
	-- the token_events trigger reads app.txn at the moment of the write.
	_txn_id := gen_random_uuid();
	perform set_config('app.txn', _txn_id::text, true);

	-- Create the tokens, owned by the destination venue, and capture their ids.
	with inserted as (
		insert into public.tokens (currency, venue, scholar)
		select _currency, _to_venue, null from generate_series(1, _amount)
		returning id
	)
	select array_agg(id) into _token_ids from inserted;

	-- Record the matching approved mint transaction (no source, to the venue).
	insert into public.transactions (
		id, creator, from_scholar, from_venue, to_scholar, to_venue,
		tokens, currency, purpose, status
	) values (
		_txn_id, _caller, null, null, null, _to_venue,
		_token_ids, _currency, _purpose, 'approved'
	);

	-- Clear it, so a later token write in this same database transaction that is
	-- NOT part of this mint is recorded as unattributed rather than borrowing this
	-- transaction's id. That is what keeps "txn is null" a trustworthy alarm.
	perform set_config('app.txn', '', true);

	-- Hand the new token ids and transaction id back to the caller.
	return jsonb_build_object('token_ids', to_jsonb(_token_ids), 'transaction_id', _txn_id);
end;
$function$;

revoke
execute on function public.mint_tokens (uuid, integer, uuid, text)
from
	public;

grant
execute on function public.mint_tokens (uuid, integer, uuid, text) to authenticated;

grant all on table public.tokens to anon;

grant all on table public.tokens to authenticated;

grant all on table public.tokens to service_role;

-- `grant all` above confers TABLE-level INSERT/UPDATE/DELETE that a policy alone
-- cannot subtract, so remove them. Tokens move only through the SECURITY DEFINER
-- RPCs, which are unaffected by grants. service_role keeps its grant for
-- administrative and recovery work.
revoke insert,
update,
delete on public.tokens
from
	authenticated,
	anon;

alter publication supabase_realtime
add table tokens;
