-- Role approvers can now compensate completed assignments directly, without
-- waiting on a minter to approve a proposed payment transaction. Tokens move
-- the moment the approver clicks Complete and pay. When the venue's reserve
-- is too small to cover the payment, the call fails, an explanatory proposed
-- mint transaction is recorded so the minter has a one-click way to top up,
-- and the application layer emails the minters about the shortfall.
--
-- The new authorization rule matches canApproveAssignment.ts in the
-- application layer:
--   1. The caller is a venue admin, OR
--   2. The caller holds an approved priority-0 assignment on this submission
--      (the "editor" of the submission), OR
--   3. The caller holds an approved assignment on this submission for the
--      role that approves the assignment's role (role.approver).
--
-- Implemented as a SECURITY DEFINER function so the authorization decision
-- lives in one place and so we can atomically check funds, move tokens,
-- record the transaction, and mark the assignment complete.

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

    -- Reassign the tokens to the scholar.
    update public.tokens
        set venue = null, scholar = _assignment.scholar
        where id = any(_token_ids);

    -- Record the approved transaction.
    insert into public.transactions (
        creator, from_scholar, from_venue, to_scholar, to_venue,
        tokens, currency, purpose, status
    ) values (
        _caller, null, _assignment.venue, _assignment.scholar, null,
        _token_ids, _venue.currency, _payment_purpose, 'approved'
    ) returning id into _txn_id;

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

revoke
execute on function public.complete_assignment (uuid, text, text)
from
	public;

grant
execute on function public.complete_assignment (uuid, text, text) to authenticated;

-- Role approvers should be able to see the transactions they themselves
-- create on behalf of the venue. The existing SELECT policy gates by
-- from/to party, venue admin, and minter; add creator to that list so an
-- approver can review their own activity even when they have no other
-- venue role.
drop policy "transactions are only visible to minters and those involved" on public.transactions;

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
