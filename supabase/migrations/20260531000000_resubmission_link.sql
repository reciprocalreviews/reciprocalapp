-- Explicit resubmission links + per-type submission cost (#124).
--
-- 1. Adds a real foreign key (submissions.previous) for on-platform predecessors,
--    keeping previousid as a free-text fallback for predecessors that aren't on
--    the platform (the multi-year transition period and bulk imports).
-- 2. Moves the author-facing submission cost from the venue (venues.submission_cost)
--    onto the submission type (submission_types.submission_cost), since each type is a
--    different amount of work. A resubmission is simply its own (revision) type, so it
--    carries its own cost — no separate resubmission cost is needed.

-- 1. Explicit foreign key to a previous submission, plus a lookup index.
alter table "public"."submissions"
add column "previous" uuid default null references public.submissions (id) on delete set null;

create index submissions_previous_index on public.submissions using btree (previous);

-- 2. Per-submission-type cost, backfilled from the venue's current submission cost.
alter table "public"."submission_types"
add column "submission_cost" integer not null default 0;

update public.submission_types st
set submission_cost = v.submission_cost
from public.venues v
where st.venue = v.id;

-- 3. Update the bulk import RPC to (a) best-effort resolve each row's free-text
-- previousid to an on-platform predecessor (exact externalid match within the
-- same venue) and store it in the new previous column, and (b) size the mint by
-- summing each row's submission type's cost.
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

revoke
execute on function public.bulk_import_submissions (uuid, jsonb, text)
from
	public;

grant
execute on function public.bulk_import_submissions (uuid, jsonb, text) to authenticated;

-- 4. Drop the now-unused venue-wide submission cost (the RPC above no longer reads it).
alter table "public"."venues"
drop column "submission_cost";
