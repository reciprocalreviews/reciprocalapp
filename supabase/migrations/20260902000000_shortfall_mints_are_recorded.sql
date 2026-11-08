-- Record the mints that cover a shortfall, so a venue's ledger accounts for them.
--
-- WHAT HAPPENED
--
-- Production mailed the stewards a ReconciliationFailed notice twice on
-- 2026-08-30 -- 03:45 and 22:15 UTC -- each reporting `conservation violations: 1`
-- and nothing else. Those are the weekly unbounded run and the nightly bounded one
-- reporting the SAME drifted holder: _since bounds checks 2, 3 and 5 and never
-- check 6, so both schedules compute conservation over the whole economy.
--
-- That the count was a NUMBER rather than the string "skipped" is itself evidence.
-- Check 6 runs only when unattributed_moves = 0 AND unattributed_mints = 0, so
-- every token in production was created and moved under an attributed transaction.
-- With replay, chain, dangling and placeholder checks all at 0 as well, nothing
-- escaped the logging trigger and nothing was altered by hand. What was left is
-- precise: for one holder the approved transactions did not sum to the tokens
-- held -- the signature of tokens CREATED inside an operation that records only a
-- MOVEMENT.
--
-- Two code paths did that, and they were the only two:
--
--   _move_tokens's _mint_shortfall branch, reached by _welcome_volunteer when a
--   venue's reserve cannot fund a newcomer's welcome grant. It minted the
--   difference into the reserve and recorded only the outbound transfer.
--
--   approve_transaction's Branch B, which pre-mints a proposal's placeholders into
--   the source reserve. Note this drifted even when the reserve was NOT short: the
--   mint is sized by _null_count, before _move_tokens looks at the reserve at all.
--
-- Both set app.txn, which is why the mints were attributed and the check ran at
-- all. Attribution and conservation are different questions -- which transaction
-- TOUCHED this token, versus was anyone CREDITED for its creation -- and this is
-- where conflating them cost something. Both now record an approved mint
-- transaction crediting the reserve, the way mint_tokens always has.
--
-- The drift already in the data is repaired by 20260902010000, which must run
-- after this so no welcome grant can re-create it behind the repair.
--
-- WHY THE DROP
--
-- _move_tokens gains _mint_creator and _mint_purpose. Postgres cannot `create or
-- replace` across a signature change -- it creates an OVERLOAD, and with an 8-arg
-- and a 10-arg version both carrying defaults every existing 6- and 7-argument
-- call becomes ambiguous and fails at runtime. Dropping first is safe: plpgsql
-- resolves callees by name at execution time, so the six callers are not
-- dependent objects.
--
-- And the ACL has to be re-applied by hand. 20260831000000 is a one-shot `do`
-- block that will not re-run, and a freshly created function inherits Supabase's
-- default privileges -- meaning this function is callable by `anon` at
-- POST /rest/v1/rpc/_move_tokens until the revoke below runs. That is the exact
-- trap 20260831000000 exists to document, and dropping a function walks back into
-- it. supabase/tests/rls/definer_grants.sql is the guard rail.
--------------------------------------

drop function if exists public._move_tokens (uuid, uuid, uuid, uuid, uuid, integer, text, boolean);

create or replace function public._move_tokens (
	_currency uuid,
	_from_scholar uuid,
	_from_venue uuid,
	_to_scholar uuid,
	_to_venue uuid,
	_amount integer,
	_shortfall_message text default 'Insufficient tokens',
	_mint_shortfall boolean default false,
	-- Who to credit the shortfall mint to. A parameter rather than auth.uid():
	-- transactions.creator is NOT NULL with an FK to scholars, and auth.uid() is
	-- null for pg_cron, a recovery script, or any service_role path -- which would
	-- turn "no session" into a constraint violation deep inside a token move.
	-- Callers that mint already know whose act caused it.
	_mint_creator uuid default null,
	_mint_purpose text default null
) returns uuid[] language plpgsql security definer
set
	search_path=public,
	pg_temp as $function$
declare
	_ids uuid[];
	_short integer;
	_moved integer;
	_minted uuid[];
	_mint_txn uuid;
	_caller_txn text;
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
	--
	-- Creating a token CREDITS the reserve, and a credit with no transaction
	-- behind it is exactly what reconcile_ledger's conservation check reports:
	-- the venue's `expected` balance stays short by every token ever minted here,
	-- permanently, because the caller only ever records the debit that follows.
	-- Attributing the mint through app.txn is NOT the same thing -- that says
	-- which transaction TOUCHED the token, not that anybody was CREDITED for its
	-- creation. The two were conflated until 2026-08-30, when the nightly check
	-- reported a venue whose own history no longer added up to its reserve.
	-- So mint the way mint_tokens does: id first, attribute, insert, record.
	--
	-- No minter check, deliberately. _move_tokens performs no authorization of
	-- its own -- that is its contract, and the one definer_grants.sql is built
	-- around -- and the welcome grant settles immediately precisely because the
	-- amount is standing venue policy rather than a decision someone makes.
	_short := _amount - cardinality(_ids);
	if _short > 0 and _mint_shortfall and _from_venue is not null then
		if _mint_creator is null then
			raise exception
				'_move_tokens cannot mint a shortfall with nobody to credit the mint to';
		end if;

		-- The MINT is its own transaction; the move below is still the caller's.
		-- Saved and restored rather than cleared, so the UPDATE at the end of this
		-- function still files under the transfer that asked for it. coalesce,
		-- because current_setting returns NULL when the GUC was never set, and
		-- set_config(NULL) resets the setting rather than blanking it.
		_caller_txn := coalesce(current_setting('app.txn', true), '');
		_mint_txn := gen_random_uuid();
		perform set_config('app.txn', _mint_txn::text, true);

		with inserted as (
			insert into public.tokens (currency, venue, scholar)
			select _currency, _from_venue, null from generate_series(1, _short)
			returning id
		)
		select array_agg(id) into _minted from inserted;

		insert into public.transactions (
			id, creator, from_scholar, from_venue, to_scholar, to_venue,
			tokens, currency, purpose, status
		) values (
			_mint_txn, _mint_creator, null, null, null, _from_venue,
			_minted, _currency,
			coalesce(_mint_purpose, 'Minted into the reserve'), 'approved'
		);

		perform set_config('app.txn', _caller_txn, true);

		_ids := _ids || _minted;
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
	boolean,
	uuid,
	text
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
	boolean,
	uuid,
	text
)
from
	public,
	anon,
	authenticated;


create or replace function public._welcome_volunteer (
	_welcomer uuid,
	_scholar uuid,
	_roleid uuid,
	_reason text
) returns integer language plpgsql security definer
set
	search_path=public,
	pg_temp as $function$
declare
	_venue public.venues;
	_txn_id uuid;
	_token_ids uuid[];
begin
	-- Find the venue that owns the role being volunteered for.
	select v.* into _venue
	from public.venues v
	join public.roles r on r.id = _roleid
	where v.id = r.venueid;
	-- Role or venue gone? Nothing to grant.
	if not found then
		return 0;
	end if;

	-- Payment-free venues have no tokens, and a zero welcome amount means there
	-- is nothing to grant — either way, do nothing.
	if _venue.payment_free or _venue.welcome_amount <= 0 then
		return 0;
	end if;

	-- Attribute both token writes below (the shortfall mint and the transfer) to
	-- the transaction recorded at the end. The id is generated up front because
	-- the tokens are written before the transaction row exists, and the
	-- token_events trigger reads app.txn at the moment of the write.
	_txn_id := gen_random_uuid();
	perform set_config('app.txn', _txn_id::text, true);

	-- Draw from the venue's reserve and move the grant to the scholar, minting
	-- only what the reserve cannot cover -- the same shape approve_transaction
	-- gives a venue-sourced transfer. _mint_shortfall rather than a count(*) and a
	-- pre-mint: the count could not see which of those tokens a concurrent payout
	-- had already locked, so a reserve that looked sufficient could still come up
	-- short. Taking first and minting the remainder is exact under concurrency,
	-- and drops a count(*) over the whole reserve from the volunteering path.
	--
	-- The last two arguments are what makes that mint accountable: _move_tokens
	-- records it as its own approved transaction crediting the reserve, so the
	-- venue's transactions still add up to the tokens it holds. Until 2026-08-30
	-- they did not, and reconcile_ledger's conservation check is what said so.
	-- _welcomer is the same person the transfer below names.
	_token_ids := public._move_tokens(
		_venue.currency, null, _venue.id, _scholar, null,
		_venue.welcome_amount, 'Insufficient tokens for the welcome grant', true,
		_welcomer, 'Minted to welcome a new volunteer'
	);

	-- Record the settled grant as one approved venue->scholar transaction.
	insert into public.transactions (
		id, creator, from_scholar, from_venue, to_scholar, to_venue,
		tokens, currency, purpose, status
	) values (
		_txn_id, _welcomer, null, _venue.id, _scholar, null,
		_token_ids, _venue.currency, _reason, 'approved'
	);

	-- Clear the attribution, so a later token write in this same database
	-- transaction that is NOT part of this grant is recorded as unattributed
	-- rather than borrowing this transaction's id.
	perform set_config('app.txn', '', true);

	-- Report what was granted, so the caller can say so precisely.
	return cardinality(_token_ids);
end;
$function$;


create or replace function public.approve_transaction (_transaction_id uuid) returns jsonb language plpgsql security definer
set
	search_path=public,
	pg_temp as $function$
declare
	_caller uuid;
	_txn public.transactions;
	_from uuid;
	_to uuid;
	_spending_own boolean;
	_null_count integer;
	_needed integer;
	_token_ids uuid[];
	_mint_txn uuid;
	_minted uuid[];
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

	-- The pure mint and the transfer below belong to this one transaction, so
	-- attribute once here. Cleared before each return so a later write in the same
	-- database transaction cannot inherit it. The shortfall mint in Branch B is the
	-- exception: it is its own transaction and sets app.txn to its own id, then
	-- restores this one for the move that follows.
	perform set_config('app.txn', _transaction_id::text, true);

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
	--
	-- A pure mint (`_from` is null) into a venue you administer is exempt: a small
	-- community's organizer may be its only minter, and the platform now discloses
	-- that arrangement on the venue page rather than forbidding it. Moving tokens
	-- that already exist into a venue you run is a different act and still refused.
	_spending_own := (_txn.from_scholar is not null and _txn.from_scholar = _caller);
	if not _spending_own then
		if _txn.to_scholar is not null and _txn.to_scholar = _caller then
			raise exception 'You cannot approve a transaction that pays you' using errcode = 'RR002';
		end if;
		if _from is not null and _txn.to_venue is not null and public.isAdmin(_txn.to_venue) then
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
		perform set_config('app.txn', '', true);
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
	--
	-- Recorded as its own approved mint transaction crediting the reserve, for the
	-- reason _move_tokens now gives: the transfer below records only the debit, so
	-- minting without a counter-entry leaves the venue permanently holding more
	-- than its own history accounts for. This drifted even when the reserve was
	-- NOT short, because the mint is sized by _null_count -- the placeholders the
	-- proposal carried -- rather than by whatever the reserve turned out to lack.
	--
	-- NOT delegated to _move_tokens(_mint_shortfall => true), which looks like the
	-- DRY move and is a security regression: the isminter gate and the amount are
	-- both pinned to _null_count here, whereas _move_tokens would size the mint by
	-- the actual shortfall at approval time. A reserve drained between proposal and
	-- approval would then turn a case that correctly raises RR003 into one minter
	-- approval authorizing an unbounded mint. Two mint sites, both correct.
	if _null_count > 0 and _txn.from_venue is not null then
		if not public.isminter(_caller, _txn.currency) then
			raise exception 'Only currency minters can mint the tokens this transaction requires';
		end if;

		_mint_txn := gen_random_uuid();
		perform set_config('app.txn', _mint_txn::text, true);

		with inserted as (
			insert into public.tokens (currency, venue, scholar)
			select _txn.currency, _txn.from_venue, null from generate_series(1, _null_count)
			returning id
		)
		select array_agg(id) into _minted from inserted;

		insert into public.transactions (
			id, creator, from_scholar, from_venue, to_scholar, to_venue,
			tokens, currency, purpose, status
		) values (
			_mint_txn, _caller, null, null, null, _txn.from_venue,
			_minted, _txn.currency,
			'Minted to complete an approved transfer', 'approved'
		);

		-- Back to the transaction being approved: the move below is its movement.
		perform set_config('app.txn', _transaction_id::text, true);
	end if;

	-- Take as many of the source's tokens as the transaction calls for, under
	-- lock, and move them to the recipient. Rolls back any mint above if the
	-- source cannot cover it.
	_needed := cardinality(_txn.tokens);
	_token_ids := public._move_tokens(
		_txn.currency, _txn.from_scholar, _txn.from_venue,
		_txn.to_scholar, _txn.to_venue,
		_needed, 'Insufficient tokens to complete the transfer'
	);

	-- Finalize the transaction with the tokens that actually moved.
	update public.transactions set status = 'approved', tokens = _token_ids where id = _transaction_id;

	perform set_config('app.txn', '', true);
	return jsonb_build_object('transaction_id', _transaction_id, 'token_ids', to_jsonb(_token_ids));
end;
$function$;


create or replace function public.conservation_violations (_currency uuid default null) returns table (
	kind text,
	holder uuid,
	currency uuid,
	expected bigint,
	actual bigint
) language sql stable security definer
set
	search_path='' as $$
	with moved as (
		select x.to_venue as holder, 'venue'::text as kind, x.currency as cur,
			sum(cardinality(x.tokens)) as n
			from public.transactions x
			where x.status = 'approved' and x.to_venue is not null
				and (_currency is null or x.currency = _currency)
			group by 1, 3
		union all
		select x.from_venue, 'venue'::text, x.currency, -sum(cardinality(x.tokens))
			from public.transactions x
			where x.status = 'approved' and x.from_venue is not null
				and (_currency is null or x.currency = _currency)
			group by 1, 3
		union all
		select x.to_scholar, 'scholar'::text, x.currency, sum(cardinality(x.tokens))
			from public.transactions x
			where x.status = 'approved' and x.to_scholar is not null
				and (_currency is null or x.currency = _currency)
			group by 1, 3
		union all
		select x.from_scholar, 'scholar'::text, x.currency, -sum(cardinality(x.tokens))
			from public.transactions x
			where x.status = 'approved' and x.from_scholar is not null
				and (_currency is null or x.currency = _currency)
			group by 1, 3
	),
	expected as (
		select m.holder, m.kind, m.cur, sum(m.n) as expected from moved m group by 1, 2, 3
	),
	actual as (
		select tk.venue as holder, 'venue'::text as kind, tk.currency as cur, count(*) as actual
			from public.tokens tk
			where tk.venue is not null and (_currency is null or tk.currency = _currency)
			group by 1, 3
		union all
		select tk.scholar, 'scholar'::text, tk.currency, count(*)
			from public.tokens tk
			where tk.scholar is not null and (_currency is null or tk.currency = _currency)
			group by 1, 3
	)
	select
		coalesce(e.kind, a.kind),
		coalesce(e.holder, a.holder),
		coalesce(e.cur, a.cur),
		coalesce(e.expected, 0)::bigint,
		coalesce(a.actual, 0)::bigint
	from expected e
	full outer join actual a
		on a.holder = e.holder and a.kind = e.kind and a.cur = e.cur
	where coalesce(e.expected, 0) <> coalesce(a.actual, 0);
$$;

alter function public.conservation_violations (uuid) OWNER to "postgres";

-- Same audience as reconcile_ledger: this describes the integrity of the whole
-- economy, and scoped to a currency it still reports every holder's balance in it.
revoke
execute on function public.conservation_violations (uuid)
from
	public,
	anon,
	authenticated;

grant
execute on function public.conservation_violations (uuid) to service_role;


create or replace function public.reconcile_ledger (_since timestamptz default null) returns jsonb language plpgsql security definer
set
	search_path='' as $$
declare
	_started timestamptz := clock_timestamp();
	_duration integer;
	_unattributed int;
	_unattributed_mints int;
	_replay int;
	_chain int;
	_placeholder int;
	_dangling int;
	_conservation jsonb;
	_conservation_n int := 0;
	_orphans int;
	_orphan_accounts int;
	_result jsonb;
	_ok boolean;
begin
	-- 1. Value that MOVED with no transaction explaining it. The single most
	-- important number here: in a healthy system it is zero, and anything else is
	-- an application bug, a migration that touched tokens directly, or someone with
	-- privileged access moving balances by hand.
	select count(*) into _unattributed
	from public.token_events
	where op = 'move' and txn is null;

	-- Tokens CREATED with no transaction explaining them. In production this is
	-- counterfeiting and should be zero. It is reported rather than failing the
	-- run, because supabase/seed.sql inserts tokens directly — every development
	-- and CI database legitimately has hundreds of these, and a check that is
	-- always red is a check nobody reads.
	select count(*) into _unattributed_mints
	from public.token_events
	where op = 'mint' and txn is null;

	-- 2. Does replaying the log still reproduce the tokens table exactly? If this
	-- drifts, either a write escaped the trigger or the log has been tampered with.
	-- Bounded by _since to the tokens that actually MOVED in the window. Replaying
	-- the whole log means a distinct-on over every event ever recorded, which is
	-- the single most expensive thing this function does; restricting it to
	-- recently-moved tokens asks the question that matters ("did anything that
	-- moved lately end up inconsistent?") at a cost that does not grow with age.
	select count(*) into _replay
	from public.tokens t
	full outer join public.tokens_as_of() a on a.token = t.id
	where (
			_since is null
			or coalesce(t.id, a.token) in (
				select e.token from public.token_events e where e.at >= _since
			)
		)
		and (
			t.id is null
			or a.token is null
			or (t.scholar, t.venue, t.currency) is distinct from (a.scholar, a.venue, a.currency)
		);

	-- 3. Each event's "previous owner" must match the prior event for that token.
	-- A break means a change happened that the trigger did not see — which a plain
	-- state comparison cannot detect, because the end state may still look right.
	-- Bounded the same way. The window function still needs each token's events in
	-- order, so the filter is on the TOKEN having moved in the window rather than
	-- on the individual event -- otherwise the first event inside the window would
	-- lose the predecessor it has to be compared against.
	select count(*) into _chain
	from (
		select
			e.prev_scholar, e.prev_venue,
			lag(e.scholar) over w as prior_scholar,
			lag(e.venue) over w as prior_venue,
			lag(e.seq) over w as prior_seq
		from public.token_events e
		where _since is null
			or e.token in (select e2.token from public.token_events e2 where e2.at >= _since)
		window w as (partition by e.token order by e.seq)
	) s
	where prior_seq is not null
		and (prev_scholar, prev_venue) is distinct from (prior_scholar, prior_venue);

	-- 4. An approved transaction still carrying placeholder UUIDs never had its
	-- tokens assigned — the amount is recorded but the movement is fiction.
	select count(*) into _placeholder
	from public.transactions
	where status = 'approved'
		and (
			'00000000-0000-0000-0000-000000000000'::uuid = any (tokens)
			or cardinality(tokens) = 0
		);

	-- 5. Every token an approved transaction cites must exist, in that currency.
	-- Bounded by transaction age. Unnesting every approved transaction's token
	-- array materializes one row per token ever moved, so this is the check whose
	-- cost is literally the platform's lifetime volume.
	select count(*) into _dangling
	from public.transactions x
	cross join lateral unnest(x.tokens) as tok(id)
	left join public.tokens t on t.id = tok.id
	where x.status = 'approved'
		and (_since is null or x.created_at >= _since)
		and tok.id <> '00000000-0000-0000-0000-000000000000'::uuid
		and (t.id is null or t.currency <> x.currency);

	-- 6. Conservation: for each holder and currency, the balance implied by
	-- approved transactions must equal the tokens actually held.
	--
	-- Only meaningful once every movement is attributed. Tokens written directly —
	-- as supabase/seed.sql does, and as any hand-repair would — exist with no
	-- transaction to account for them, so this would report drift that check 1 has
	-- already explained. Skipped rather than reported as a false violation.
	if _unattributed = 0 and _unattributed_mints = 0 then
		select coalesce(jsonb_agg(to_jsonb(v)), '[]'::jsonb), count(*)
		into _conservation, _conservation_n
		from public.conservation_violations() v;
	else
		_conservation := to_jsonb('skipped: unattributed token provenance present'::text);
	end if;

	-- 7. A proposal with no supporters is the signature of proposeVenue crashing
	-- between its two client-side writes — the proposal exists and the record of
	-- who proposed it does not.
	select count(*) into _orphans
	from public.proposals p
	where not exists (select 1 from public.supporters s where s.proposalid = p.id);

	-- 8. An account with no scholar row. A scholar row is created once, by the
	-- on_auth_user_created trigger, and never again — so an account that misses it is
	-- permanently unusable: the session is valid, but the app reads its signed-in
	-- scholar from this table and finds nothing, so the person is rendered as anonymous
	-- with no way to recover. It happened in production, to a real scholar, and nothing
	-- here noticed. ensure_scholar now repairs it on their next load; this is what says
	-- it needed repairing, which matters because the likeliest cause is the trigger
	-- itself going missing — and that trigger lives on auth.users, outside the schema
	-- set the drift guard compares.
	select count(*) into _orphan_accounts
	from auth.users u
	where not exists (select 1 from public.scholars s where s.id = u.id);

	-- `ok` covers only what must hold in EVERY environment. The advisory block
	-- below is real signal in production but expected to be non-zero anywhere
	-- seeded by supabase/seed.sql, and folding it into `ok` would make local and CI
	-- runs permanently red — which is how a monitoring check becomes wallpaper.
	--
	-- orphan_accounts is NOT advisory, and can afford not to be: seed.sql inserts
	-- auth.users rows and only ever UPDATEs public.scholars, so it already depends on
	-- the trigger to create them. A seeded database with no trigger is a broken one,
	-- and going red is the correct response to it.
	_ok := _unattributed = 0
		and _replay = 0
		and _chain = 0
		and _placeholder = 0
		and _dangling = 0
		and _orphan_accounts = 0
		and _conservation_n = 0;

	_result := jsonb_build_object(
		'ok', _ok,
		'invariants', jsonb_build_object(
			'unattributed_moves', _unattributed,
			'replay_mismatches', _replay,
			'chain_breaks', _chain,
			'placeholders_in_approved', _placeholder,
			'dangling_token_refs', _dangling,
			'conservation_violations', _conservation,
			'orphan_accounts', _orphan_accounts
		),
		-- Watch these on production, where both should be zero.
		'advisory', jsonb_build_object(
			'unattributed_mints', _unattributed_mints,
			'orphan_proposals', _orphans
		)
	);

	_duration := (extract(epoch from clock_timestamp() - _started) * 1000)::integer;
	_result := jsonb_set(_result, '{window}', case when _since is null
		then to_jsonb('all history'::text) else to_jsonb(_since) end);
	_result := jsonb_set(_result, '{duration_ms}', to_jsonb(_duration));

	insert into public.reconciliations (ok, result, duration_ms) values (_ok, _result, _duration);

	-- A check nobody is told about is wallpaper. On failure this goes three ways:
	-- the reconciliations table for history, the Postgres log for anyone looking at
	-- the project, and email to the stewards so it reaches a person.
	--
	-- Inserted directly rather than through queue_email: that RPC resolves
	-- recipients from a caller's scholar ids and is built for the authenticated
	-- request path, whereas this runs from pg_cron with no caller at all. The
	-- INSERT is available here because this function is SECURITY DEFINER and owned
	-- by postgres; the revoke that closed the open-relay hole applies to
	-- authenticated and anon.
	--
	-- One row to the shared steward inbox rather than one per steward. The old
	-- per-steward fan-out required a VERIFIED contact address, which meant the
	-- check that reports the ledger is broken could itself reach nobody — the
	-- worst possible thing to be conditional. The alias always resolves.
	if not _ok then
		raise warning 'reconcile_ledger found violations: %', _result;

		insert into public.emails (event, email, scholar, args)
		values (
			'ReconciliationFailed',
			public.steward_inbox(),
			null,
			jsonb_build_array(
				to_char(now() at time zone 'utc', 'YYYY-MM-DD HH24:MI') || ' UTC',
				-- A compact summary rather than raw JSON: the recipient needs to know
				-- which checks failed and how badly, not to parse a payload.
				concat_ws(', ',
					nullif('unattributed moves: ' || _unattributed, 'unattributed moves: 0'),
					nullif('replay mismatches: ' || _replay, 'replay mismatches: 0'),
					nullif('chain breaks: ' || _chain, 'chain breaks: 0'),
					nullif('approved transactions holding placeholders: ' || _placeholder, 'approved transactions holding placeholders: 0'),
					nullif('dangling token references: ' || _dangling, 'dangling token references: 0'),
					nullif('conservation violations: ' || _conservation_n, 'conservation violations: 0'),
					nullif('accounts with no scholar row: ' || _orphan_accounts, 'accounts with no scholar row: 0')
				)
			)
		);
	end if;

	return _result;
end;
$$;
