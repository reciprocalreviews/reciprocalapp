-- Submission completion as a guarded action.
--
-- A submission is "done" only when every non-editor assignment that was
-- approved has been compensated, and the editor(s) themselves have been
-- compensated as part of the same action. The editor flipping the status
-- to 'done' IS the act of compensating themselves -- it isn't two steps.
--
-- We forbid writing submissions.status and submissions.completed_at directly
-- from the application layer by revoking column-level UPDATE privileges.
-- The mark_submission_done() RPC bypasses those revokes via SECURITY DEFINER
-- so that all transitions to 'done' go through one place where the
-- "everyone compensated" invariant is checked. Once 'done', the columns
-- cannot be changed by anyone -- reopening is forbidden by design.

-- 1. Add the completion timestamp to submissions.
alter table public.submissions
add column completed_at timestamp with time zone default null;

-- 2. Add the per-venue "recently done" visibility window. The submissions
--    list hides done submissions older than this many days.
alter table public.venues
add column done_visibility_days integer not null default 30
    check (done_visibility_days >= 0 and done_visibility_days <= 365);

-- 3. Lock down submission completion state from direct UPDATEs. Application
--    code routes through the RPC below; everything else (title, expertise,
--    note, etc.) still updates through the existing editor RLS policy.
revoke update (status, completed_at) on public.submissions from authenticated;

-- 4. The RPC. Returns one of:
--    { status: 'blocked', blockers: [{role_name, scholar_id}, ...] }
--    { status: 'insufficient', shortfall, total_amount, mint_transaction_id }
--    { status: 'completed', transactions: [...], total_amount, recipients: [...] }
--
-- Raises on unauthenticated, missing submission, already-done, missing editor
-- assignment, or missing compensation configuration for an editor role.
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

            update public.tokens
                set venue = null, scholar = _editor.scholar_id
                where id = any(_token_ids);

            insert into public.transactions (
                creator, from_scholar, from_venue, to_scholar, to_venue,
                tokens, currency, purpose, status
            ) values (
                _caller, null, _submission.venue, _editor.scholar_id, null,
                _token_ids, _venue.currency, _payment_purpose, 'approved'
            ) returning id into _txn_id;

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

revoke
execute on function public.mark_submission_done (uuid, text, text)
from
    public;

grant
execute on function public.mark_submission_done (uuid, text, text) to authenticated;
