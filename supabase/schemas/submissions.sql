/* SCHEMA  */
-- The status of a submission, in relation to payments.
create type public.submission_status as enum('reviewing', 'done');

alter type public.submission_status OWNER to "postgres";

create table submissions (
	-- The unique ID of the submission
	id uuid not null default gen_random_uuid() primary key,
	-- The venue to which the submission corresponds
	venue uuid not null references venues (id),
	-- The external unique identifier of the submission, such as a submission number or manuscript number
	externalid text not null,
	-- An optional free-text link to a previous external submission id, for a predecessor that is not (yet)
	-- on this platform. Retained for bulk import and the multi-year transition period.
	previousid text default null,
	-- An optional explicit foreign key to a previous submission on this platform (a resubmission chain).
	-- Null if there is no on-platform predecessor.
	previous uuid default null references submissions (id) on delete set null,
	-- The submission type of the paper
	submission_type uuid not null references submission_types (id),
	-- The scholars associated with the submission. The non-empty requirement is
	-- waived for imported rows: a bulk import knows the manuscript exists before it
	-- knows who on this platform wrote it.
	authors uuid[] not null constraint submissions_authors_check check (imported or cardinality(authors)>0),
	-- The token amounts proposed for the submission, corresponding to the authors
	payments integer[] not null constraint submissions_payments_nonempty_check check (imported or cardinality(payments)>0),
	-- The transactions corresponding to the payments, corresponding to the authors. Null uuid of not yet paid.
	transactions uuid[] not null constraint submissions_transactions_nonempty_check check (imported or cardinality(transactions)>0),
	-- The three arrays stay aligned whether or not the row was imported.
	constraint submissions_check check (cardinality(payments)=cardinality(authors)),
	constraint submissions_check1 check (cardinality(transactions)=cardinality(authors)),
	-- An optional title for public bidding
	title text not null default ''::text,
	-- An optional description of expertise required for public bidding
	expertise text default null,
	-- The status of the submission in relation to payments.
	status submission_status not null default 'reviewing',
	-- When the submission was marked done (null while still under review).
	-- Set by the mark_submission_done RPC; cannot be reverted.
	completed_at timestamp with time zone default null,
	-- True when the row came from bulk_import_submissions rather than an author
	-- submitting through the app. Imported rows are exempt from the non-empty
	-- author/payment/transaction checks above, because a bulk import records that a
	-- manuscript exists before anyone has paid for it.
	imported boolean not null default false,
	-- Free text an editor may attach; also carries the bulk import's note.
	note text,
	-- Added with bulk import so imported rows have a meaningful ordering. UTC
	-- explicitly rather than now(), so it does not depend on the server timezone.
	created_at timestamp with time zone not null default timezone('utc'::text, now())
);

alter table public.submissions OWNER to "postgres";

-- One row per manuscript per venue. Bulk import relies on this to resolve a
-- previousid to an on-platform predecessor unambiguously.
create unique index if not exists submissions_venue_externalid_unique on public.submissions using btree (venue, externalid);

grant all on table public.submissions to "anon";

grant all on table public.submissions to "authenticated";

grant all on table public.submissions to "service_role";

-- Lock the completion state (status, completed_at) from direct UPDATEs: only the
-- mark_submission_done RPC (SECURITY DEFINER) may write them. A column-level
-- revoke is ineffective while authenticated holds the TABLE-level UPDATE granted
-- by `grant all` above, so remove the table-level UPDATE and re-grant only the
-- editable columns. (The author list among these is further gated to priority-0
-- assigned scholars by the enforce_submission_author_edits trigger.)
revoke update on public.submissions from authenticated;

grant update (
	venue, externalid, previousid, previous, submission_type, authors, payments, transactions, title, expertise
) on public.submissions to authenticated;

--------------------------------------
-- Indexes

create index submissions_previous_index on public.submissions using btree (previous);

create index submissions_scholar_index on public.submissions using btree (authors);

create index submissions_venue_index on public.submissions using btree (venue);

--------------------------------------
-- Security
alter table public.submissions ENABLE row LEVEL SECURITY;

-- Select policy is in assignments.sql, after assignments table is declared.
create policy "anyone can create submissions, admins for imports" on "public"."submissions" as permissive for insert to authenticated
with
	check (
		(not imported)
		or public.isadmin (venue)
	);

create policy "admins can delete submissions" on public.submissions for DELETE to authenticated using (public.isAdmin (venue));

--------------------------------------
-- RPCs (defined in migration 20260608000000_atomic_crud.sql)
-- create_submission: create the proposed payment transactions for each paying
-- author, immediately approve the submitter's own charge (moving their tokens to
-- the venue), and insert the submission with aligned authors/payments/
-- transactions arrays — all atomically, so a partial failure can't orphan
-- proposed transactions or violate the array-cardinality CHECK constraints.
-- Author resolution and balance pre-checks (reads) stay in the application
-- layer; this function receives already-resolved author ids and charges.
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

revoke execute on function public.create_submission (uuid, text, text, uuid, uuid, uuid[], integer[], text, text, text, text) from public;
grant execute on function public.create_submission (uuid, text, text, uuid, uuid, uuid[], integer[], text, text, text, text) to authenticated;

alter publication supabase_realtime
add table submissions;

--------------------------------------
-- RPC (authoritative definition from migration 20260531000000_resubmission_link)
create or replace function public.bulk_import_submissions (
	_venueid uuid,
	_submissions jsonb,
	_import_note text
) returns jsonb language plpgsql security definer
set
	search_path=public,
	pg_temp as $function$
declare
    _admin_id uuid;
    _currency uuid;
    _count integer;
    _mint_amount integer;
    _submission_ids uuid[];
    _new_submission_id uuid;
    _transaction_id uuid;
    _row jsonb;
    _previousid text;
    _previous uuid;
    _type_cost integer;
    _tokens uuid[];
begin
    _admin_id := (select auth.uid());

    if _admin_id is null then
        raise exception 'Authentication required';
    end if;

    if not public.isadmin(_venueid) then
        raise exception 'Only venue admins can bulk import submissions';
    end if;

    select currency into _currency
    from public.venues
    where id = _venueid;

    if _currency is null then
        raise exception 'Venue not found';
    end if;

    _count := jsonb_array_length(_submissions);
    if _count = 0 then
        raise exception 'No submissions provided';
    end if;

    _mint_amount := 0;

    _submission_ids := array[]::uuid[];
    for _row in select * from jsonb_array_elements(_submissions)
    loop
        _previousid := nullif(_row->>'previousid', '');

        -- Best-effort resolve the free-text predecessor to an on-platform
        -- submission in this venue. Unresolved (off-platform) predecessors
        -- keep previousid only, with previous left null.
        _previous := null;
        if _previousid is not null then
            select id into _previous
            from public.submissions
            where venue = _venueid and externalid = _previousid
            limit 1;
        end if;

        insert into public.submissions (
            venue,
            externalid,
            previousid,
            previous,
            authors,
            payments,
            transactions,
            title,
            expertise,
            submission_type,
            note,
            imported
        ) values (
            _venueid,
            _row->>'externalid',
            _previousid,
            _previous,
            array[]::uuid[],
            array[]::integer[],
            array[]::uuid[],
            coalesce(_row->>'title', ''),
            nullif(_row->>'expertise', ''),
            (_row->>'submission_type')::uuid,
            nullif(_row->>'note', ''),
            true
        ) returning id into _new_submission_id;
        _submission_ids := _submission_ids || _new_submission_id;

        -- Each row bills its submission type's cost.
        select submission_cost into _type_cost
        from public.submission_types
        where id = (_row->>'submission_type')::uuid;
        _mint_amount := _mint_amount + coalesce(_type_cost, 0);
    end loop;

    if _mint_amount > 0 then
        _tokens := array_fill('00000000-0000-0000-0000-000000000000'::uuid, array[_mint_amount]);

        insert into public.transactions (
            creator,
            from_scholar,
            from_venue,
            to_scholar,
            to_venue,
            tokens,
            currency,
            purpose,
            status
        ) values (
            _admin_id,
            null,
            null,
            null,
            _venueid,
            _tokens,
            _currency,
            coalesce(nullif(_import_note, ''), 'Mint to fund imported pre-launch submissions'),
            'proposed'
        ) returning id into _transaction_id;
    end if;

    return jsonb_build_object(
        'submission_ids', to_jsonb(_submission_ids),
        'transaction_id', _transaction_id,
        'mint_amount', _mint_amount
    );
end;
$function$;

--------------------------------------
-- RPC (authoritative definition from migration 20260804020000_token_event_attribution)
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
