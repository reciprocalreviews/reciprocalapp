-- close_submission: an editor settles every outstanding assignment on a submission -- paying
-- the ones whose work was done, removing the ones whose work was not -- and marks it done, in
-- one step. Marking done used to wait on every reviewer requesting compensation first. The
-- revoke travels in this migration: Supabase's default privileges grant anon EXECUTE on a
-- function every time it is created.

--------------------------------------
-- close_submission: settle every outstanding assignment and mark the submission done, in
-- one step.
--
-- mark_submission_done refuses while any approved non-editor assignment is uncompensated,
-- and compensation is pull-based: it waits on each reviewer following the link in the
-- decision email and requesting it. A reviewer who never does held the submission open
-- indefinitely, and the editor -- who sent the decision in the reviewing platform, not
-- here -- had no prompt to come back. This lets the editor close it out when they do come
-- back, saying for each outstanding assignment whether the work was done (pay it) or not
-- (remove it).
--
-- _pay and _remove must together name exactly the outstanding assignments, with no
-- overlap, so a page loaded before another assignment was approved cannot close over it
-- unseen. The reserve is checked against the whole payout -- reviewers and editors -- up
-- front, so a short reserve proposes one mint for the whole shortfall and pays nobody,
-- rather than paying some and leaving the rest for a retry.
--
-- Each payment goes through complete_assignment and the final step through
-- mark_submission_done, so authorization, transaction attribution and the status flip have
-- one definition each. Anything they report other than success rolls the whole close back.
create or replace function public.close_submission (
	_submission_id uuid,
	_pay uuid[],
	_remove uuid[],
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
    _pay_ids uuid[] := coalesce(_pay, '{}');
    _remove_ids uuid[] := coalesce(_remove, '{}');
    _outstanding uuid[];
    _total_amount integer;
    _unpriced boolean;
    _available integer;
    _shortfall integer;
    _mint_txn_id uuid;
    _assignment record;
    _result jsonb;
    _payouts jsonb := '[]'::jsonb;
    _removed jsonb := '[]'::jsonb;
    _done jsonb;
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

    -- The same authorization as mark_submission_done, checked here too so a caller who
    -- could not close the submission learns nothing from the checks below.
    if not exists (
        select 1
        from public.assignments a
        join public.roles r on r.id = a.role
        where a.submission = _submission_id
          and a.scholar = _caller
          and a.approved
          and r.priority = 0
    ) then
        raise exception 'Only an approved editor (priority-0) can close this submission';
    end if;

    -- The outstanding assignments: mark_submission_done's blockers.
    select coalesce(array_agg(a.id), '{}') into _outstanding
    from public.assignments a
    join public.roles r on r.id = a.role
    where a.submission = _submission_id
      and a.approved
      and not a.completed
      and r.priority > 0;

    if _pay_ids && _remove_ids then
        raise exception 'An assignment cannot be both paid and removed';
    end if;
    if not (
        (_pay_ids || _remove_ids) @> _outstanding
        and _outstanding @> (_pay_ids || _remove_ids)
        and cardinality(_pay_ids || _remove_ids) = cardinality(_outstanding)
    ) then
        raise exception 'The assignments to pay and remove must be exactly the outstanding ones; reload and try again';
    end if;

    -- Everything this close pays: the assignments being paid, then the editors. _pay is a
    -- subset of the outstanding assignments, so every id in it is on this submission.
    select coalesce(sum(c.amount), 0), coalesce(bool_or(c.amount is null), false)
    into _total_amount, _unpriced
    from public.assignments a
    join public.roles r on r.id = a.role
    left join public.compensation c
        on c.role = a.role and c.submission_type = _submission.submission_type
    where a.id = any(_pay_ids)
       or (a.submission = _submission_id and a.approved and not a.completed and r.priority = 0);
    if _unpriced then
        raise exception 'No compensation amount is configured for one or more roles on this submission';
    end if;

    select count(*) into _available from public.tokens
        where venue = _submission.venue and currency = _venue.currency;

    if _available < _total_amount then
        _shortfall := _total_amount - _available;
        insert into public.transactions (
            creator, from_scholar, from_venue, to_scholar, to_venue,
            tokens, currency, purpose, status
        ) values (
            _caller, null, null, null, _submission.venue,
            array_fill('00000000-0000-0000-0000-000000000000'::uuid, array[_shortfall]),
            _venue.currency,
            replace(
                replace(
                    replace(
                        replace(_mint_purpose_template, '{amount}', _total_amount::text),
                        '{role}', 'editor'
                    ),
                    '{title}', _submission.title
                ),
                '{shortfall}', _shortfall::text
            ),
            'proposed'
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

    -- Remove first: an assignment the editor says was not done is not someone the
    -- approver may pay, and must not be left behind to block the status flip.
    -- Who was removed, and from what, travels back so the caller can tell each of them:
    -- losing pay for work they may believe they did is not something to learn by silence.
    for _assignment in
        select a.id, a.role, a.scholar, r.name as role_name
        from public.assignments a join public.roles r on r.id = a.role
        where a.id = any(_remove_ids)
    loop
        if not public.can_approve_assignment(_submission_id, _assignment.role) then
            raise exception 'You are not authorized to remove this assignment';
        end if;
        delete from public.assignments where id = _assignment.id;
        _removed := _removed || jsonb_build_object(
            'scholar_id', _assignment.scholar,
            'role_name', _assignment.role_name
        );
    end loop;

    for _assignment in
        select a.id from public.assignments a where a.id = any(_pay_ids) order by a.id
    loop
        _result := public.complete_assignment(
            _assignment.id, _payment_purpose_template, _mint_purpose_template
        );
        if _result->>'status' <> 'transferred' then
            raise exception 'Insufficient tokens to compensate this submission'
                using errcode = 'RR003';
        end if;
        _payouts := _payouts || jsonb_build_object(
            'transaction_id', _result->'transaction_id',
            'scholar_id', _result->'scholar_id',
            'role_name', _result->'role_name',
            'amount', _result->'amount'
        );
    end loop;

    _done := public.mark_submission_done(
        _submission_id, _payment_purpose_template, _mint_purpose_template
    );
    if _done->>'status' <> 'completed' then
        raise exception 'Insufficient tokens to compensate this submission''s editors'
            using errcode = 'RR003';
    end if;

    return jsonb_build_object(
        'status', 'completed',
        'submission_id', _submission_id,
        'venue_id', _submission.venue,
        'currency_id', _venue.currency,
        'total_amount', _total_amount,
        'payouts', _payouts || coalesce(_done->'payouts', '[]'::jsonb),
        'removed', _removed
    );
end;
$function$;

revoke
execute on function public.close_submission (uuid, uuid[], uuid[], text, text)
from
	public,
	anon;

grant
execute on function public.close_submission (uuid, uuid[], uuid[], text, text) to authenticated;
