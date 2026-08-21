-- Attribute every token movement to the transaction that caused it.
--
-- 20260804010000 made token_events capture every ownership change. This makes
-- each captured row say WHY it happened, by having the RPCs publish the relevant
-- transaction id through the `app.txn` GUC immediately before they touch
-- `public.tokens`; the logging trigger reads it at the moment of the write.
--
-- The payoff is a single number:
--
--     select count(*) from public.token_events where op = 'move' and txn is null;
--
-- In a healthy system that is zero. Anything else is value that moved without a
-- transaction explaining it — an application bug, a migration that touched
-- tokens directly, or someone with privileged access moving balances by hand.
-- Nothing else in this schema can tell you that, because `tokens` has no history
-- and `transactions` is a parallel narrative rather than a derivation.
--
-- Two details that make the signal trustworthy:
--
--   * The GUC is transaction-local (set_config's third argument is true), so it
--     cannot leak across pooled connections.
--   * Each RPC CLEARS it once its own writes are done. Without that, an
--     unattributed write later in the same database transaction would silently
--     borrow the previous statement's id, and the alarm would read clean while
--     being wrong.
--
-- Three of these functions move tokens BEFORE the transaction row exists, so
-- they generate the id up front with gen_random_uuid() and insert it explicitly
-- rather than taking it from `returning id`. The column allowlists added in
-- 20260802010000 do not restrict them: they are SECURITY DEFINER and run as the
-- owner.
--
-- The bodies below are otherwise unchanged from their previous definitions.

--------------------------------------
-- mint_tokens
create or replace function public.mint_tokens (
	_currency uuid,
	_amount integer,
	_to_venue uuid,
	_purpose text
) returns jsonb language plpgsql security definer
set
	search_path = public, pg_temp as $function$
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

--------------------------------------
-- transfer_tokens
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

	-- Attribute the movement to its transaction. coalesce because finalizing a
	-- proposed transfer reuses that transaction's id, while a fresh transfer needs
	-- one generated up front: the tokens move before its row is written.
	_txn_id := coalesce(_transaction, gen_random_uuid());
	perform set_config('app.txn', _txn_id::text, true);

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

--------------------------------------
-- approve_transaction
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

	perform set_config('app.txn', '', true);
	return jsonb_build_object('transaction_id', _transaction_id, 'token_ids', to_jsonb(_token_ids));
end;
$function$;

--------------------------------------
-- create_submission
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
	search_path = public, pg_temp as $function$
declare
	_caller uuid;
	_currency uuid;
	_transactions uuid[] := array[]::uuid[];
	_i integer;
	_author uuid;
	_payment integer;
	_txn_id uuid;
	_token_ids uuid[];
	_submission_id uuid;
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
			-- Take exactly _payment of the submitter's tokens in this currency.
			select array_agg(id) into _token_ids
			from (
				select id from public.tokens
				where currency = _currency and scholar = _caller
				order by id limit _payment
			) sub;
			-- Can't pay? Abort the whole submission (everything rolls back). RR003
			-- surfaces the specific "insufficient tokens" message.
			if _token_ids is null or cardinality(_token_ids) < _payment then
				raise exception 'You do not have enough tokens to pay your submission charge' using errcode = 'RR003';
			end if;
			update public.tokens set scholar = null, venue = _venue where id = any(_token_ids);
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

	-- Return the new submission id.
	return jsonb_build_object('submission_id', _submission_id);
end;
$function$;

--------------------------------------
-- complete_assignment
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

    -- Authorize the caller. Mirrors canApproveAssignment.ts.
    if not (
        public.isAdmin(_assignment.venue)
        or exists (
            select 1
            from public.assignments a
            join public.roles r on r.id = a.role
            where a.submission = _assignment.submission
              and a.scholar = _caller
              and a.approved
              and r.priority = 0
        )
        or (
            _role.approver is not null
            and exists (
                select 1
                from public.assignments a
                where a.submission = _assignment.submission
                  and a.scholar = _caller
                  and a.role = _role.approver
                  and a.approved
            )
        )
    ) then
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

    -- Pick the tokens to move. Order is stable but arbitrary.
    select array_agg(id) into _token_ids from (
        select id from public.tokens
            where venue = _assignment.venue and currency = _venue.currency
            order by id
            limit _amount
    ) sub;

    -- Attribute the payout to its transaction. Generated up front: the tokens
    -- move before the transaction row exists, and the token_events trigger reads
    -- app.txn at the moment of the write.
    _txn_id := gen_random_uuid();
    perform set_config('app.txn', _txn_id::text, true);

    -- Reassign the tokens to the scholar.
    update public.tokens
        set venue = null, scholar = _assignment.scholar
        where id = any(_token_ids);

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

--------------------------------------
-- mark_submission_done
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

            select array_agg(id) into _token_ids from (
                select id from public.tokens
                    where venue = _submission.venue and currency = _venue.currency
                    order by id
                    limit _editor.amount
            ) sub;

            -- Per editor, not once for the call: each payout is its own
            -- transaction, so one GUC for the whole function would file every
            -- movement under the last editor's id.
            _txn_id := gen_random_uuid();
            perform set_config('app.txn', _txn_id::text, true);

            update public.tokens
                set venue = null, scholar = _editor.scholar_id
                where id = any(_token_ids);

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
