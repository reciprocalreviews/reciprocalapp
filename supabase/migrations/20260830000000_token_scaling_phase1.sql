-- Token scaling, phase 1: correctness.
--
-- Three things, all of which only show up once a venue holds more tokens than a
-- test fixture does:
--
-- 1. INDEXES. Every hot token query filters on a holder AND a currency, but
--    `tokens` carried only single-column indexes, so the planner had to
--    BitmapAnd two of them and recheck the currency from the heap. The six
--    selection sites also carried an `order by id` that pinned nothing -- tokens
--    are fungible, and the old comment beside one of them said so outright --
--    while talking the planner into walking tokens_pkey instead. That bet is
--    backwards here, because these RPCs always drained the lowest ids first, so
--    a reserve accumulates high-id tokens and the pkey walk passes every token
--    already spent: 35ms per transfer on a 500,000-token fixture, against 0.05ms
--    once the ordering is gone.
--
-- 2. LOCKING. Six RPCs picked tokens with `order by id limit N` and then moved
--    them with `where id = any(...)` -- no lock on the select, no ownership
--    predicate on the update. Under READ COMMITTED two concurrent draws on one
--    holder select THE SAME ROWS, and the second overwrites the first after it
--    commits: both callers report success, both write a transactions row, and
--    the first recipient's tokens are gone. The holder's count(*) stays
--    consistent, which is why nothing noticed. See public._move_tokens.
--
-- 3. COUNTING. Balances are count(*) over `tokens`, and the app read them by
--    fetching one ROW PER TOKEN and taking the array length in the browser.
--    PostgREST caps responses at max_rows (1000) and truncation is not an error,
--    so those counts silently stopped at 1000: a quarter-million-token reserve
--    reported 1000, and the affordability check refused submissions the author
--    could pay for. currency_holder_counts and scholar_balances count in the
--    database instead.

--------------------------------------
-- 1. Indexes
-- Holder leading (not currency) because getScholarTokenCount runs on every
-- navigation and filters on `scholar` alone; a currency-leading index could not
-- serve it, and these would have to sit alongside the single-column ones rather
-- than replacing them. Partial because check_owner already guarantees exactly
-- one of scholar/venue is non-null.
create index if not exists tokens_scholar_currency_id_index on public.tokens using btree (scholar, currency, id)
where
	scholar is not null;

create index if not exists tokens_venue_currency_id_index on public.tokens using btree (venue, currency, id)
where
	venue is not null;

-- Now redundant prefixes of the two above.
drop index if exists public.tokens_scholar_index;

drop index if exists public.tokens_venue_index;

-- tokens_currency_index stays: currency-wide aggregates (total supply, distinct
-- holders) filter on that column alone and are a prefix of neither composite.

--------------------------------------
-- 2. Moving tokens under lock
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

alter function public._move_tokens (uuid, uuid, uuid, uuid, uuid, integer, text, boolean) OWNER to "postgres";

-- A step of the RPCs below, not an entry point: it moves value with no
-- authorization of its own, so only the definer functions that have already
-- authorized the move may call it.
revoke
execute on function public._move_tokens (uuid, uuid, uuid, uuid, uuid, integer, text, boolean)
from
	public;

--------------------------------------
-- 3. Counting in the database
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

create or replace function public.scholar_balances (_currency uuid, _scholars uuid[]) returns table (scholar uuid, count bigint) language sql stable security definer
set
	search_path='' as $function$
	select t.scholar, count(*)
	from public.tokens t
	where t.currency = _currency
		and t.scholar = any (_scholars)
	group by t.scholar;
$function$;

alter function public.scholar_balances (uuid, uuid[]) OWNER to "postgres";

revoke
execute on function public.scholar_balances (uuid, uuid[])
from
	public;

grant
execute on function public.scholar_balances (uuid, uuid[]) to authenticated;

--------------------------------------
-- 4. The six callers, each now taking its tokens through _move_tokens.
-- Bodies are otherwise unchanged; authorization, attribution and the
-- transactions they record are all as they were.

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
	search_path=public,
	pg_temp as $function$
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

	-- Attribute the movement to its transaction. coalesce because finalizing a
	-- proposed transfer reuses that transaction's id, while a fresh transfer needs
	-- one generated up front: the tokens move before its row is written. Set
	-- before the move, not after, because the token_events trigger reads app.txn
	-- at the moment of each write.
	_txn_id := coalesce(_transaction, gen_random_uuid());
	perform set_config('app.txn', _txn_id::text, true);

	-- Take exactly _amount of the source's tokens under lock and reassign them to
	-- the destination. RR003 lets the app show the specific "insufficient tokens"
	-- message (see SupabaseCRUD.rpcErrorKey).
	_token_ids := public._move_tokens(
		_currency, _from_scholar, _from_venue, _to_scholar, _to_venue,
		_amount, 'Insufficient tokens to transfer'
	);

	if _transaction is not null then
		-- Finalizing a previously proposed transfer: flip it to approved and
		-- record which tokens actually moved.
		update public.transactions set status = 'approved', tokens = _token_ids where id = _transaction;
		_txn_id := _transaction;
	else
		-- A fresh transfer (e.g. a gift): record a new approved transaction.
		insert into public.transactions (
			id, creator, from_scholar, from_venue, to_scholar, to_venue,
			tokens, currency, purpose, status
		) values (
			_txn_id, _caller, _from_scholar, _from_venue, _to_scholar, _to_venue,
			_token_ids, _currency, _purpose, 'approved'
		);
	end if;

	perform set_config('app.txn', '', true);

	-- Return the transaction id and the tokens that moved.
	return jsonb_build_object('transaction_id', _txn_id, 'token_ids', to_jsonb(_token_ids));
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

	-- Every token write below — the pure mint, the shortfall mint, and the
	-- transfer — belongs to this one transaction, so attribute once here. Cleared
	-- before each return so a later write in the same database transaction cannot
	-- inherit it.
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
	if _null_count > 0 and _txn.from_venue is not null then
		if not public.isminter(_caller, _txn.currency) then
			raise exception 'Only currency minters can mint the tokens this transaction requires';
		end if;
		insert into public.tokens (currency, venue, scholar)
		select _txn.currency, _txn.from_venue, null from generate_series(1, _null_count);
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
	_token_ids := public._move_tokens(
		_venue.currency, null, _venue.id, _scholar, null,
		_venue.welcome_amount, 'Insufficient tokens for the welcome grant', true
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

create or replace function public.complete_assignment (
	_assignment_id uuid,
	_payment_purpose_template text,
	_mint_purpose_template text
) returns jsonb language plpgsql security definer
set
	search_path=public,
	pg_temp as $function$
declare
    _caller uuid;
    _assignment public.assignments;
    _role public.roles;
    _venue public.venues;
    _submission public.submissions;
    _amount integer;
    _available integer;
    _token_ids uuid[];
    _txn_id uuid;
    _mint_txn_id uuid;
    _shortfall integer;
    _mint_purpose text;
    _payment_purpose text;
begin
    _caller := (select auth.uid());
    if _caller is null then
        raise exception 'Authentication required';
    end if;

    select * into _assignment from public.assignments where id = _assignment_id;
    if not found then
        raise exception 'Assignment not found';
    end if;
    if _assignment.completed then
        raise exception 'Assignment is already completed';
    end if;
    if not _assignment.approved then
        raise exception 'Assignment must be approved before it can be completed';
    end if;

    select * into _role from public.roles where id = _assignment.role;
    if not found then
        raise exception 'Role not found';
    end if;

    -- Authorize the caller against the single definition of the rule. The same
    -- three branches are asserted in TypeScript by canApproveAssignment.unit.ts
    -- and in SQL by atomic_crud_rpc.sql, over the same table of cases.
    if not public.can_approve_assignment(_assignment.submission, _assignment.role) then
        raise exception 'You are not authorized to compensate this assignment';
    end if;

    select * into _venue from public.venues where id = _assignment.venue;
    if not found then
        raise exception 'Venue not found';
    end if;

    select * into _submission from public.submissions where id = _assignment.submission;
    if not found then
        raise exception 'Submission not found';
    end if;

    select amount into _amount from public.compensation
        where role = _assignment.role and submission_type = _submission.submission_type;
    if _amount is null then
        raise exception 'No compensation amount is configured for this role and submission type';
    end if;

    -- Substitute named placeholders in the localized purpose template.
    -- Supported placeholders: {role}, {title}, {amount}, {shortfall}.
    _payment_purpose := replace(
        replace(_payment_purpose_template, '{role}', _role.name),
        '{title}', _submission.title
    );

    -- How many tokens does the venue actually hold in this currency?
    select count(*) into _available from public.tokens
        where venue = _assignment.venue and currency = _venue.currency;

    if _available < _amount then
        _shortfall := _amount - _available;
        _mint_purpose := replace(
            replace(
                replace(
                    replace(_mint_purpose_template, '{amount}', _amount::text),
                    '{role}', _role.name
                ),
                '{title}', _submission.title
            ),
            '{shortfall}', _shortfall::text
        );

        -- Record a proposed mint so the minter has a pre-explained item to
        -- approve in the venue transactions page.
        insert into public.transactions (
            creator, from_scholar, from_venue, to_scholar, to_venue,
            tokens, currency, purpose, status
        ) values (
            _caller, null, null, null, _assignment.venue,
            array_fill('00000000-0000-0000-0000-000000000000'::uuid, array[_shortfall]),
            _venue.currency, _mint_purpose, 'proposed'
        ) returning id into _mint_txn_id;

        return jsonb_build_object(
            'status', 'insufficient',
            'shortfall', _shortfall,
            'amount', _amount,
            'mint_transaction_id', _mint_txn_id,
            'venue_id', _assignment.venue,
            'venue_title', _venue.title,
            'currency_id', _venue.currency,
            'scholar_id', _assignment.scholar,
            'submission_id', _assignment.submission,
            'role_name', _role.name
        );
    end if;

    -- Attribute the payout to its transaction. Generated up front: the tokens
    -- move before the transaction row exists, and the token_events trigger reads
    -- app.txn at the moment of the write.
    _txn_id := gen_random_uuid();
    perform set_config('app.txn', _txn_id::text, true);

    -- Take the tokens under lock and reassign them to the scholar. The count
    -- above decided whether to propose a mint; this can still come up short if a
    -- concurrent payout holds the rows it counted, which RR003 reports as a
    -- retryable shortfall rather than paying out tokens the venue no longer has.
    _token_ids := public._move_tokens(
        _venue.currency, null, _assignment.venue, _assignment.scholar, null,
        _amount, 'Insufficient tokens to compensate this assignment'
    );

    -- Record the approved transaction.
    insert into public.transactions (
        id, creator, from_scholar, from_venue, to_scholar, to_venue,
        tokens, currency, purpose, status
    ) values (
        _txn_id, _caller, null, _assignment.venue, _assignment.scholar, null,
        _token_ids, _venue.currency, _payment_purpose, 'approved'
    );

    perform set_config('app.txn', '', true);

    -- Mark the assignment completed.
    update public.assignments set completed = true where id = _assignment_id;

    return jsonb_build_object(
        'status', 'transferred',
        'transaction_id', _txn_id,
        'amount', _amount,
        'role_name', _role.name,
        'venue_id', _assignment.venue,
        'scholar_id', _assignment.scholar,
        'submission_id', _assignment.submission
    );
end;
$function$;

create or replace function public.create_submission (
	_venue uuid,
	_external_id text,
	_previous_id text,
	_previous uuid,
	_submission_type uuid,
	_authors uuid[],
	_payments integer[],
	_title text,
	_expertise text,
	_note text,
	_purpose text
) returns jsonb language plpgsql security definer
set
	search_path=public,
	pg_temp as $function$
declare
	_caller uuid;
	_currency uuid;
	_cost integer;
	_transactions uuid[] := array[]::uuid[];
	_i integer;
	_author uuid;
	_payment integer;
	_txn_id uuid;
	_token_ids uuid[];
	_submission_id uuid;
	_editor_role uuid;
	_editors uuid[];
	_editor uuid;
begin
	-- Identify and require an authenticated caller (the submitter).
	_caller := (select auth.uid());
	if _caller is null then
		raise exception 'Authentication required';
	end if;
	-- Every author must have a corresponding payment, and there must be one.
	if cardinality(_authors) <> cardinality(_payments) then
		raise exception 'Authors and payments must align';
	end if;
	if cardinality(_authors) = 0 then
		raise exception 'A submission needs at least one author';
	end if;

	-- Only a listed author may create a submission, unless the caller is a venue
	-- admin adding one manually. RR009 surfaces the specific message.
	if not (_caller = any(_authors) or public.isadmin(_venue)) then
		raise exception 'Only a listed author or a venue admin can create a submission'
			using errcode = 'RR009';
	end if;

	-- No author may be listed twice. The loop below indexes _authors positionally,
	-- so a repeat would be charged twice for one manuscript.
	if cardinality(_authors) <> (select count(distinct a) from unnest(_authors) a) then
		raise exception 'A submission cannot list the same author more than once'
			using errcode = 'RR008';
	end if;

	-- The type must belong to this venue, and the charges must add up to its cost.
	select submission_cost into _cost
	from public.submission_types
	where id = _submission_type and venue = _venue;
	if _cost is null then
		raise exception 'Submission type not found for this venue';
	end if;
	-- sum() ignores NULLs and returns NULL over an empty set; the loop below reads
	-- a NULL payment as 0, so coalesce here to agree with it. Payment-free venues
	-- have zero-cost types and zero payments, so this holds as 0 = 0.
	if coalesce((select sum(p) from unnest(_payments) p), 0) <> _cost then
		raise exception 'Author payments must add up to the submission cost of %', _cost
			using errcode = 'RR007';
	end if;

	-- Charges are denominated in the venue's currency.
	select currency into _currency from public.venues where id = _venue;
	if _currency is null then
		raise exception 'Venue not found';
	end if;

	-- Build the parallel transactions[] array, one entry per author.
	for _i in 1 .. cardinality(_authors) loop
		_author := _authors[_i];
		_payment := _payments[_i];

		-- A non-paying co-author (zero charge) gets a placeholder, not a
		-- transaction — there is nothing to collect from them.
		if coalesce(_payment, 0) = 0 then
			_transactions := _transactions || '00000000-0000-0000-0000-000000000000'::uuid;
			continue;
		end if;

		-- Record this author's charge as a proposed scholar->venue payment.
		insert into public.transactions (
			creator, from_scholar, from_venue, to_scholar, to_venue,
			tokens, currency, purpose, status
		) values (
			_caller, _author, null, null, _venue,
			array_fill('00000000-0000-0000-0000-000000000000'::uuid, array[_payment]),
			_currency, _purpose, 'proposed'
		) returning id into _txn_id;

		-- Attribute this author's token movement to this author's charge. Set inside
		-- the loop, not once for the function: each author is a separate transaction,
		-- and one GUC for the whole call would file every movement under the last id.
		perform set_config('app.txn', _txn_id::text, true);

		-- The submitter's own charge is settled now: move their tokens to the
		-- venue and approve the transaction. Co-authors approve theirs later.
		if _author = _caller then
			-- Take exactly _payment of the submitter's tokens under lock and move
			-- them to the venue. Can't pay? Abort the whole submission (everything
			-- rolls back); RR003 surfaces the specific "insufficient tokens" message.
			_token_ids := public._move_tokens(
				_currency, _caller, null, null, _venue,
				_payment, 'You do not have enough tokens to pay your submission charge'
			);
			update public.transactions set status = 'approved', tokens = _token_ids where id = _txn_id;
		end if;

		perform set_config('app.txn', '', true);

		_transactions := _transactions || _txn_id;
	end loop;

	-- Insert the submission with the three aligned arrays. The equal-cardinality
	-- CHECK constraints hold because we appended exactly one entry per author.
	insert into public.submissions (
		venue, externalid, previousid, previous, submission_type,
		authors, payments, transactions, title, expertise, note
	) values (
		_venue, _external_id, _previous_id, _previous, _submission_type,
		_authors, _payments, _transactions, coalesce(_title, ''), _expertise, _note
	) returning id into _submission_id;

	-- Seat the venue's editor, when there is exactly one it could be.
	--
	-- A priority-0 assignment is also a compensation commitment: mark_submission_done
	-- pays every approved priority-0 assignment on the submission. So this only fires
	-- when the choice is unambiguous. Several eligible editors would mean an arbitrary
	-- pick, and seating them all would mean several editor fees per paper; a sole editor
	-- who is an author here would be editing their own submission. In any of those cases
	-- nobody is seated, and the caller notifies the candidates instead.
	select r.id into _editor_role
	from public.roles r
	where r.venueid = _venue and r.priority = 0
	order by r.id
	limit 1;

	if _editor_role is not null then
		select array_agg(v.scholarid) into _editors
		from public.volunteers v
		where v.roleid = _editor_role and v.active and v.accepted = 'accepted';

		if cardinality(coalesce(_editors, array[]::uuid[])) = 1
			and not (_editors[1] = any(_authors)) then
			_editor := _editors[1];
			insert into public.assignments (venue, submission, scholar, role, bid, approved)
			values (_venue, _submission_id, _editor, _editor_role, false, true);
		end if;
	end if;

	-- Return the new submission id, and who is editing it. A null editor is the
	-- caller's cue to send the "this submission needs an editor" notice instead of
	-- the "you were assigned one" notice.
	return jsonb_build_object('submission_id', _submission_id, 'editor', _editor);
end;
$function$;

create or replace function public.mark_submission_done (
	_submission_id uuid,
	_payment_purpose_template text,
	_mint_purpose_template text
) returns jsonb language plpgsql security definer
set
	search_path=public,
	pg_temp as $function$
declare
    _caller uuid;
    _submission public.submissions;
    _venue public.venues;
    _blockers jsonb;
    _editor_assignments jsonb;
    _total_amount integer := 0;
    _available integer;
    _shortfall integer;
    _mint_purpose text;
    _payment_purpose text;
    _mint_txn_id uuid;
    _payouts jsonb := '[]'::jsonb;
    _editor record;
    _token_ids uuid[];
    _txn_id uuid;
begin
    _caller := (select auth.uid());
    if _caller is null then
        raise exception 'Authentication required';
    end if;

    select * into _submission from public.submissions where id = _submission_id;
    if not found then
        raise exception 'Submission not found';
    end if;
    if _submission.status = 'done' then
        raise exception 'Submission is already done';
    end if;

    select * into _venue from public.venues where id = _submission.venue;
    if not found then
        raise exception 'Venue not found';
    end if;

    -- Authorize: caller must hold an approved priority-0 assignment on this
    -- submission. Venue admin alone is insufficient -- they must also be
    -- assigned as the editor to make the completion (and self-compensation)
    -- decision.
    if not exists (
        select 1
        from public.assignments a
        join public.roles r on r.id = a.role
        where a.submission = _submission_id
          and a.scholar = _caller
          and a.approved
          and r.priority = 0
    ) then
        raise exception 'Only an approved editor (priority-0) can mark this submission done';
    end if;

    -- Find blockers: any non-editor (priority > 0) assignment that is
    -- approved but not yet completed. These must be completed individually
    -- (via complete_assignment) before the submission can be marked done.
    select jsonb_agg(
        jsonb_build_object(
            'assignment_id', a.id,
            'role_id', r.id,
            'role_name', r.name,
            'scholar_id', a.scholar
        )
    ) into _blockers
    from public.assignments a
    join public.roles r on r.id = a.role
    where a.submission = _submission_id
      and a.approved
      and not a.completed
      and r.priority > 0;

    if _blockers is not null then
        return jsonb_build_object(
            'status', 'blocked',
            'blockers', _blockers
        );
    end if;

    -- Gather priority-0 assignments that still need compensation, along
    -- with their per-(role, submission_type) compensation amounts.
    select jsonb_agg(
        jsonb_build_object(
            'assignment_id', a.id,
            'role_id', r.id,
            'role_name', r.name,
            'scholar_id', a.scholar,
            'amount', c.amount
        ) order by a.id
    ) into _editor_assignments
    from public.assignments a
    join public.roles r on r.id = a.role
    left join public.compensation c
        on c.role = a.role and c.submission_type = _submission.submission_type
    where a.submission = _submission_id
      and a.approved
      and not a.completed
      and r.priority = 0;

    -- Validate compensation is configured for every uncompleted editor
    -- assignment. We refuse to mark done with a partial editor payout.
    if exists (
        select 1 from jsonb_array_elements(coalesce(_editor_assignments, '[]'::jsonb)) e
        where (e->>'amount') is null
    ) then
        raise exception 'No compensation amount is configured for one or more editor roles on this submission';
    end if;

    -- Sum the total tokens needed for all editor payouts.
    select coalesce(sum((e->>'amount')::integer), 0) into _total_amount
    from jsonb_array_elements(coalesce(_editor_assignments, '[]'::jsonb)) e;

    if _total_amount > 0 then
        -- Check venue reserve in the venue's currency.
        select count(*) into _available from public.tokens
            where venue = _submission.venue and currency = _venue.currency;

        if _available < _total_amount then
            _shortfall := _total_amount - _available;
            _mint_purpose := replace(
                replace(
                    replace(
                        replace(_mint_purpose_template, '{amount}', _total_amount::text),
                        '{role}', 'editor'
                    ),
                    '{title}', _submission.title
                ),
                '{shortfall}', _shortfall::text
            );

            -- Record a proposed mint covering the entire shortfall so a
            -- minter has a pre-explained item to approve. Do NOT flip
            -- status -- the editor must retry mark_submission_done after
            -- the mint is approved.
            insert into public.transactions (
                creator, from_scholar, from_venue, to_scholar, to_venue,
                tokens, currency, purpose, status
            ) values (
                _caller, null, null, null, _submission.venue,
                array_fill('00000000-0000-0000-0000-000000000000'::uuid, array[_shortfall]),
                _venue.currency, _mint_purpose, 'proposed'
            ) returning id into _mint_txn_id;

            return jsonb_build_object(
                'status', 'insufficient',
                'shortfall', _shortfall,
                'total_amount', _total_amount,
                'mint_transaction_id', _mint_txn_id,
                'venue_id', _submission.venue,
                'venue_title', _venue.title,
                'currency_id', _venue.currency,
                'submission_id', _submission_id
            );
        end if;

        -- We can cover all editor payouts. Compensate each one atomically.
        for _editor in
            select
                (e->>'assignment_id')::uuid as assignment_id,
                (e->>'role_id')::uuid as role_id,
                (e->>'role_name') as role_name,
                (e->>'scholar_id')::uuid as scholar_id,
                (e->>'amount')::integer as amount
            from jsonb_array_elements(_editor_assignments) e
        loop
            _payment_purpose := replace(
                replace(_payment_purpose_template, '{role}', _editor.role_name),
                '{title}', _submission.title
            );

            -- Per editor, not once for the call: each payout is its own
            -- transaction, so one GUC for the whole function would file every
            -- movement under the last editor's id. Set before the move, because
            -- the token_events trigger reads app.txn at the moment of each write.
            _txn_id := gen_random_uuid();
            perform set_config('app.txn', _txn_id::text, true);

            -- Take this editor's payout under lock and move it. The reserve check
            -- above covered the whole payout run, but each editor draws from the
            -- same reserve in turn, so a concurrent payout can still make a later
            -- editor short -- RR003 rolls the whole run back rather than paying
            -- some editors and silently skipping others.
            _token_ids := public._move_tokens(
                _venue.currency, null, _submission.venue, _editor.scholar_id, null,
                _editor.amount, 'Insufficient tokens to compensate this submission''s editors'
            );

            insert into public.transactions (
                id, creator, from_scholar, from_venue, to_scholar, to_venue,
                tokens, currency, purpose, status
            ) values (
                _txn_id, _caller, null, _submission.venue, _editor.scholar_id, null,
                _token_ids, _venue.currency, _payment_purpose, 'approved'
            );

            perform set_config('app.txn', '', true);

            update public.assignments set completed = true where id = _editor.assignment_id;

            _payouts := _payouts || jsonb_build_object(
                'transaction_id', _txn_id,
                'scholar_id', _editor.scholar_id,
                'role_name', _editor.role_name,
                'amount', _editor.amount
            );
        end loop;
    end if;

    -- Flip the status. This is the only path that can write status='done'
    -- or completed_at, because the application layer's UPDATE privilege on
    -- those columns is revoked above.
    update public.submissions
        set status = 'done', completed_at = now()
        where id = _submission_id;

    return jsonb_build_object(
        'status', 'completed',
        'submission_id', _submission_id,
        'venue_id', _submission.venue,
        'currency_id', _venue.currency,
        'total_amount', _total_amount,
        'payouts', _payouts
    );
end;
$function$;
