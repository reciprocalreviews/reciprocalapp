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
-- Currency-wide aggregates (total supply, distinct holders) filter on this
-- column alone, so it stays even though it is a prefix of neither composite
-- below.
create index tokens_currency_index on public.tokens using btree (currency);

-- Every hot query filters on a HOLDER and a CURRENCY: `count(*) where venue = $1
-- and currency = $2` for the balance checks, and `where ... limit N` for the six
-- selection sites in _move_tokens' callers. With single-column indexes the
-- planner had to BitmapAnd two of them and recheck the currency from the heap,
-- over the holder's entire balance. With the holder leading and the currency
-- second both shapes become index range scans that stop after N rows; `id`
-- trails so the index also covers `select id`, which is all either shape reads.
--
-- The holder leads rather than the currency because `getScholarTokenCount` runs
-- on every navigation and filters on `scholar` alone; a currency-leading index
-- could not serve it, and these would then have to sit alongside the
-- single-column ones rather than replacing them.
--
-- Partial because `check_owner` already guarantees exactly one of the two is
-- non-null, so each index covers half the table.
create index tokens_scholar_currency_id_index on public.tokens using btree (scholar, currency, id)
where
	scholar is not null;

create index tokens_venue_currency_id_index on public.tokens using btree (venue, currency, id)
where
	venue is not null;

--------------------------------------
-- Security
alter table public.tokens ENABLE row LEVEL SECURITY;

-- Balances are private (#109). This policy used to be `using (true)`, so every
-- signed-in scholar could read who held how much of what across every venue on
-- the platform -- by listing this table directly, whatever the UI chose to show.
--
-- Two branches, and deliberately no more. Both are plain column comparisons, so
-- this stays exactly as cheap as `using (true)` was and the composite indexes
-- above still serve it: a policy is evaluated once PER ROW, and a token table
-- has a row per token, so anything cleverer here is paid for a quarter of a
-- million times per venue.
--
-- Cross-scholar reads are not served by this policy at all. They go through
-- public.scholar_balances, which is SECURITY DEFINER and asks
-- public.can_see_balances ONCE per call rather than once per row -- the same
-- division of labour every other RPC in this schema uses, and the reason the
-- audience rule can be as broad as it is without costing anything.
create policy "tokens are visible to their holder, and venue reserves to any scholar" on public.tokens for
select
	to authenticated using (
		-- Your own balance. Null-safe by construction: a venue-held row has
		-- `scholar is null`, and `null = uuid` is null, not true.
		scholar=(
			select
				auth.uid ()
		)
		-- A venue's reserve, which is institutional rather than personal. A scholar
		-- deciding whether to volunteer somewhere is entitled to know whether the
		-- venue can actually pay, and #109 is about what individuals hold.
		or venue is not null
	);

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
-- re-implements the tokens INSERT policy (caller must be a minter).
--
-- Minting into a venue the caller administers is permitted: a small community's
-- organizer is often its only minter, and refusing left such a venue unable to
-- hold any tokens at all. The overlap is disclosed on the venue page instead of
-- being forbidden here (see 20260828000020_admin_minter_overlap_allowed.sql).
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

--------------------------------------
-- A NOTE ON `revoke ... from public` THROUGHOUT THIS SCHEMA
--
-- It is not sufficient on its own. Supabase's default privileges grant anon,
-- authenticated and service_role EXECUTE on every function created in `public`
-- BEFORE the revoke runs, and revoking from PUBLIC does not remove an explicit
-- per-role grant -- so a function that reads as owner-only here can still be
-- called by anyone at POST /rest/v1/rpc/<name>. The same trap is documented for
-- TABLES in token_events.sql and below; it applies to FUNCTIONS too, and nobody
-- had looked until #109.
--
-- Every SECURITY DEFINER function's real audience is therefore set in one place,
-- 20260831000000_definer_function_grants.sql, which revokes from public, anon AND
-- authenticated and then grants back by category. `supabase db diff` does NOT
-- compare function ACLs, so CI cannot catch a regression here -- the guard rail is
-- supabase/tests/rls/definer_grants.sql. Add a function, add it to both.
--------------------------------------
-- Moving tokens
-- _move_tokens: take _amount of _currency from the source, reassign them to the
-- destination, and return the ids that moved. Every path that moves existing
-- value goes through here -- transfer_tokens, approve_transaction,
-- _welcome_volunteer, complete_assignment, create_submission and
-- mark_submission_done -- so the concurrency rules below are written once
-- instead of six times.
--
-- WHY THE LOCK
--
-- Each of those callers used to run `select id from tokens where <holder> order
-- by id limit N` and then `update tokens ... where id = any(_token_ids)`, with no
-- lock on the select and no ownership predicate on the update. Under READ
-- COMMITTED two concurrent draws on the same holder see the same snapshot and,
-- because the order is `id` and therefore deterministic, select THE SAME ROWS.
-- The second update blocks on the first's row locks and then -- since
-- `id = any(...)` is still true once the first commits -- overwrites them. Both
-- callers report success and both write a transactions row, but the first
-- recipient's tokens are gone. The holder's count(*) stays consistent, which is
-- exactly why nothing noticed: only reconcile_ledger's conservation check would
-- have caught it, a day later.
--
-- Unreachable serially. Reachable with two editors compensating reviewers at
-- once, and likeliest during a launch burst of welcome grants -- which is to say,
-- at the moment a large community arrives.
--
-- SKIP LOCKED rather than a plain FOR UPDATE: blocking would serialize every
-- payout in a busy venue behind one another on the same lowest ids. Skipping
-- makes concurrent draws disjoint, and turns RR003 from "the holder lacks the
-- tokens" into "the holder lacks AVAILABLE tokens" -- which is the accurate
-- claim, and retryable.
create or replace function public._move_tokens (
	_currency uuid,
	_from_scholar uuid,
	_from_venue uuid,
	_to_scholar uuid,
	_to_venue uuid,
	_amount integer,
	_shortfall_message text default 'Insufficient tokens',
	_mint_shortfall boolean default false
) returns uuid[] language plpgsql security definer
set
	search_path=public,
	pg_temp as $function$
declare
	_ids uuid[];
	_short integer;
	_moved integer;
begin
	-- Nothing to move is not an error; several callers compute the amount.
	if _amount is null or _amount <= 0 then
		return '{}'::uuid[];
	end if;
	if num_nonnulls(_from_scholar, _from_venue) <> 1 then
		raise exception '_move_tokens requires exactly one source';
	end if;
	if num_nonnulls(_to_scholar, _to_venue) <> 1 then
		raise exception '_move_tokens requires exactly one destination';
	end if;

	-- Two branches rather than one OR'd predicate. The single-query form needs
	-- `(_from_scholar is not null and scholar = _from_scholar) or (...)`, where one
	-- side of each conjunct is a plpgsql variable -- which the planner cannot
	-- reduce to a single index scan, so it BitmapOrs or scans and never reaches
	-- the composite indexes above. The caller always knows which case it is.
	--
	-- And NO `order by id`, which every one of these six call sites used to carry.
	-- Tokens are fungible -- the comment at the old complete_assignment site said
	-- so outright, "order is stable but arbitrary" -- so the ordering pinned
	-- nothing anyone could observe, and it cost two things. It made concurrent
	-- draws contend for exactly the same lowest ids, and it talked the planner out
	-- of these indexes: with `order by id limit N` it walks tokens_pkey instead,
	-- betting it will hit N matching rows almost immediately. That bet is exactly
	-- backwards here, because this function always drains the lowest ids first, so
	-- a reserve accumulates high-id tokens and the pkey walk has to pass every
	-- token already spent. Measured on a 500,000-token fixture: 35ms with the
	-- ordering, 0.05ms without.
	if _from_scholar is not null then
		select array_agg(id) into _ids from (
			select id from public.tokens
			where scholar = _from_scholar and currency = _currency
			limit _amount
			for update skip locked
		) sub;
	else
		select array_agg(id) into _ids from (
			select id from public.tokens
			where venue = _from_venue and currency = _currency
			limit _amount
			for update skip locked
		) sub;
	end if;
	_ids := coalesce(_ids, '{}'::uuid[]);

	-- Callers whose contract is "grant this much" rather than "spend what is
	-- held" cover the difference by minting into the source venue. Rows this
	-- transaction just inserted are invisible to everyone else, so they need no
	-- lock and cannot be contended.
	_short := _amount - cardinality(_ids);
	if _short > 0 and _mint_shortfall and _from_venue is not null then
		with inserted as (
			insert into public.tokens (currency, venue, scholar)
			select _currency, _from_venue, null from generate_series(1, _short)
			returning id
		)
		select _ids || array_agg(id) into _ids from inserted;
		_short := 0;
	end if;

	if _short > 0 then
		raise exception '%', _shortfall_message using errcode = 'RR003';
	end if;

	-- Re-assert ownership in the UPDATE itself. The lock above makes this
	-- redundant today, and that is the point: it is what keeps a future caller
	-- that reaches these rows by some other route from moving tokens the source
	-- no longer holds. A mismatch means the premise of this move was false, so
	-- fail rather than write.
	if _from_scholar is not null then
		update public.tokens set scholar = _to_scholar, venue = _to_venue
		where id = any(_ids) and scholar = _from_scholar and currency = _currency;
	else
		update public.tokens set scholar = _to_scholar, venue = _to_venue
		where id = any(_ids) and venue = _from_venue and currency = _currency;
	end if;
	get diagnostics _moved = row_count;
	if _moved <> cardinality(_ids) then
		raise exception '%', _shortfall_message using errcode = 'RR003';
	end if;

	return _ids;
end;
$function$;

alter function public._move_tokens (
	uuid,
	uuid,
	uuid,
	uuid,
	uuid,
	integer,
	text,
	boolean
) OWNER to "postgres";

-- A step of the RPCs above, not an entry point: it moves value with no
-- authorization of its own, so only the definer functions that have already
-- authorized the move may call it.
revoke
execute on function public._move_tokens (
	uuid,
	uuid,
	uuid,
	uuid,
	uuid,
	integer,
	text,
	boolean
)
from
	public,
	anon,
	authenticated;

--------------------------------------
-- Reading balances
-- Balances are count(*) over this table, and until these existed the app read
-- them by fetching one ROW PER TOKEN and taking the array length in the browser.
-- PostgREST caps a response at `max_rows` (1000), and truncation is not an error,
-- so every one of those counts silently stopped at 1000 -- a venue reserve of a
-- quarter-million tokens reported 1000, and the affordability check refused
-- submissions authors could pay for. Counting belongs in the database.
-- currency_holder_counts: the three numbers the currency page shows -- total
-- supply, how many scholars hold any, how many venues hold any. count(distinct)
-- ignores nulls, which is exactly the "held by a scholar" / "held by a venue"
-- split that check_owner guarantees.
create or replace function public.currency_holder_counts (_currency uuid) returns jsonb language sql stable security definer
set
	search_path='' as $function$
	select jsonb_build_object(
		'supply', count(*),
		'scholars', count(distinct t.scholar),
		'venues', count(distinct t.venue)
	)
	from public.tokens t
	where t.currency = _currency;
$function$;

alter function public.currency_holder_counts (uuid) OWNER to "postgres";

revoke
execute on function public.currency_holder_counts (uuid)
from
	public;

grant
execute on function public.currency_holder_counts (uuid) to authenticated;

-- can_see_balances: may the caller see OTHER scholars' balances in this currency?
--
-- #109 resolved: balances are not public, and no feature is wanted to make them
-- public. The audience is the people who run and staff the reviewing the currency
-- pays for -- they decide who to assign and who is undercompensated, and DESIGN.md
-- asks them to prioritize the scholars most in need of paid work, which is not a
-- judgement anyone can make blind.
--
-- Deliberately NOT the authors of a submission. An author can reach a submission
-- page and see who is reviewing it, but what those reviewers hold is none of their
-- business -- and before this, the submission page showed it to them, and encoded
-- it a second time in the row order.
--
-- Takes a currency rather than a row, so a caller evaluates it ONCE. Keeping this
-- out of the tokens policy is the whole reason the audience can be this broad
-- without costing anything per row.
create or replace function public.can_see_balances (_currency uuid) returns boolean language sql stable security definer
set
	search_path='' as $function$
	select
		-- Minters answer for the currency's supply.
		public.isminter((select auth.uid()), _currency)
		-- Venue admins, who need not be volunteers anywhere.
		or exists (
			select 1 from public.venues ve
			where ve.currency = _currency
				and (select auth.uid()) = any (ve.admins)
		)
		-- The reviewing pool: anyone holding an accepted, still-active role at a
		-- venue using this currency. `active` matters -- unvolunteering keeps the
		-- row (it is what stops a welcome grant being made twice), so accepting
		-- alone would leave visibility behind forever.
		or exists (
			select 1
			from public.volunteers v
			join public.roles r on r.id = v.roleid
			join public.venues ve on ve.id = r.venueid
			where v.scholarid = (select auth.uid())
				and v.accepted = 'accepted'
				and v.active
				and ve.currency = _currency
		);
$function$;

alter function public.can_see_balances (uuid) OWNER to "postgres";

revoke
execute on function public.can_see_balances (uuid)
from
	public,
	anon;

grant
execute on function public.can_see_balances (uuid) to authenticated;

-- scholar_balances: how many tokens of one currency each named scholar holds.
-- An RPC rather than a PostgREST aggregate because the scholar list is a venue's
-- whole volunteer roster: as a `in.(...)` query string, five thousand UUIDs is a
-- ~185 KB URL and a 414 before Postgres ever sees it, and the grouped result was
-- itself subject to max_rows. As an argument it travels in the POST body.
--
-- SECURITY DEFINER, so it bypasses RLS and must re-implement the rule itself --
-- which is the point: the tokens policy stays a two-column comparison and the
-- audience question is asked here, once. Before #109 this function had no checks
-- at all, and since scholars.id is publicly readable, an attacker could harvest
-- every id and reconstruct the platform's entire balance table from it.
--
-- Filters rather than raising. A caller outside the audience still gets their own
-- row: a reviewer's submission page must not error just because they may not see
-- their peers' balances, it must simply stop showing them.
--
-- Scholars holding none are absent rather than zero; every caller defaults.
create or replace function public.scholar_balances (_currency uuid, _scholars uuid[]) returns table (scholar uuid, count bigint) language sql stable security definer
set
	search_path='' as $function$
	select t.scholar, count(*)
	from public.tokens t
	where t.currency = _currency
		and t.scholar = any (_scholars)
		and (
			-- Your own balance is always yours to see.
			t.scholar = (select auth.uid())
			-- Everyone else's, only for the currency's reviewing audience. Constant
			-- for the call, so it is evaluated once and not once per token.
			or public.can_see_balances(_currency)
		)
	group by t.scholar;
$function$;

alter function public.scholar_balances (uuid, uuid[]) OWNER to "postgres";

revoke
execute on function public.scholar_balances (uuid, uuid[])
from
	public;

grant
execute on function public.scholar_balances (uuid, uuid[]) to authenticated;

-- authors_can_cover: can each of these scholars afford the charge beside them?
--
-- The new-submission form has to tell a submitter which co-authors cannot cover
-- their share, or the submission fails at create_submission with an RR003 nobody
-- can act on. But the submitter is usually outside the balance audience -- being
-- someone's co-author confers nothing -- so scholar_balances rightly returns them
-- nothing, and the form would report every co-author as broke.
--
-- So this answers the question the form actually asks. It returns a BOOLEAN per
-- author and never an amount: "Amara cannot cover her share" is what the
-- submitter needs, and is strictly less than the exact shortfall the form used to
-- disclose about people who never agreed to share it.
--
-- Deliberately not gated on can_see_balances: a yes/no about a charge the
-- submitter is themselves proposing is a much smaller disclosure than a balance,
-- and gating it would break co-authored submissions entirely.
create or replace function public.authors_can_cover (
	_currency uuid,
	_scholars uuid[],
	_amounts integer[]
) returns table (scholar uuid, covered boolean) language sql stable security definer
set
	search_path='' as $function$
	select
		a.scholar,
		(
			select count(*) from public.tokens t
			where t.currency = _currency and t.scholar = a.scholar
		) >= a.amount
	from unnest(_scholars, _amounts) as a (scholar, amount);
$function$;

alter function public.authors_can_cover (uuid, uuid[], integer[]) OWNER to "postgres";

revoke
execute on function public.authors_can_cover (uuid, uuid[], integer[])
from
	public,
	anon;

grant
execute on function public.authors_can_cover (uuid, uuid[], integer[]) to authenticated;

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

-- Deliberately NOT in supabase_realtime, for the reason token_events.sql already
-- gives for staying out of it: "a 500-token mint would fan 500 rows out to every
-- connected client, each firing invalidateAll()". That argument was always just
-- as true of `tokens` itself, which is one row per token -- so moving N tokens
-- emitted N messages to every client watching the venue or the scholar, and each
-- one re-ran every load function on their page.
--
-- The UI it fed loses nothing. `transactions` is published, and it is ONE row per
-- movement whatever the amount, so the venue layout and the header balance
-- subscribe to that instead and refresh on exactly the same events.
