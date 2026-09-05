-- Let a bulk import name the scholar to seat on each submission, in a role the
-- importing admin chooses.
--
-- WHY
--
-- An import could seat an editor only when the venue had exactly one accepted,
-- active volunteer in its top-priority role (20260828040000). That rule is right
-- for what it does -- with several editors the choice would be arbitrary -- but it
-- leaves every venue that has more than one editor importing a whole backlog with
-- nobody on it, which is the case a backlog import is usually for. Exports name a
-- handling editor per manuscript; the information was there and we were throwing it
-- away.
--
-- The role is chosen per import rather than fixed at priority 0, because venues are
-- not shaped alike: one venue's per-paper editor column names its associate editors
-- (priority 1) while another's names the people who hold the top role. Fixing it at
-- priority 0 would have made the column useless to the first kind of venue and would
-- have quietly handed out editorial authority at the second.
--
-- WHAT IS CHECKED HERE, AND WHY HERE
--
-- The client resolves a written name to a scholar id against the venue's own
-- volunteers and refuses to submit a row it could not resolve. This function checks
-- the same things again -- that the role belongs to the venue, and that the scholar
-- already holds it, accepted and active -- because a rule that lives only in a form
-- is a rule that holds only for people who use the form, which is the same reason
-- create_submission re-checks its own charges (RR007/RR008). Without it, a bulk
-- import would be an API-level way for a venue admin to grant a priority-0 seat:
-- approve any assignment on the submission, edit its author list, mark it done, and
-- be paid for it by mark_submission_done.
--
-- A failed check raises, which rolls the entire import back. That is deliberate: a
-- partially seated batch is harder to reason about than no batch, and since the
-- client already blocked this case, arriving here means the form was bypassed.
--
-- AT MOST ONE PRIORITY-0 SEAT PER ROW
--
-- The sole-editor fallback still runs, except on a row that named somebody for the
-- editor role itself. Seating both would put two priority-0 assignments on one
-- submission, and marking a submission done pays every approved priority-0
-- assignment on it -- an editor's compensation per editor per paper, which is the
-- reason the original rule refused to choose among several editors at all.
--
-- Seating a role below priority 0 has a different and intended consequence: that
-- assignment blocks mark_submission_done until it has been compensated, and is paid
-- from the venue reserve at the (submission type, role) rate. The import's own mint
-- covers it, since a submission type's cost must be at least the compensation paid
-- out for it.
--
-- THE SIGNATURE DOES NOT CHANGE
--
-- The person and their role ride in the per-row jsonb rather than as new arguments.
-- `create or replace` on an unchanged signature keeps the function's OID, and with
-- it the `grant execute to authenticated` that 20260831000000 attached -- so there
-- is no drop, no re-grant, and no change to the generated client types. A new
-- parameter with a default would have been worse than one without: Postgres would
-- have created a second overload, left the old one in place and granted, and made
-- PostgREST's resolution ambiguous.
--
-- ON RLS
--
-- The assignments insert bypasses the assignments INSERT policy because this
-- function is SECURITY DEFINER. It grants no authority the caller did not have: the
-- caller was already required to be a venue admin above, and that policy admits an
-- admin of the venue anyway.
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
    _editor_role uuid;
    _editors uuid[];
    _editor uuid;
    _seated integer := 0;
    _row_person uuid;
    _row_role uuid;
    _row_priority integer;
    _seated_by jsonb := '{}'::jsonb;
    _waiting integer := 0;
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

    -- Resolve the venue's sole editor once, on the same unambiguous-only rule as
    -- create_submission. Imported rows carry no authors, so the "not an author of this
    -- paper" half of that rule has nothing to test here.
    select r.id into _editor_role
    from public.roles r
    where r.venueid = _venueid and r.priority = 0
    order by r.id
    limit 1;

    if _editor_role is not null then
        select array_agg(v.scholarid) into _editors
        from public.volunteers v
        where v.roleid = _editor_role and v.active and v.accepted = 'accepted';

        if cardinality(coalesce(_editors, array[]::uuid[])) = 1 then
            _editor := _editors[1];
        end if;
    end if;

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

        -- A row may name the scholar to seat on it, in a role the importing admin
        -- chose. The client resolves the name to an id and checks eligibility before
        -- sending; it is re-checked here because a rule that lives only in the form
        -- is a rule that holds only for people who use the form -- the same reason
        -- create_submission re-checks its own charges. Raising rolls the whole import
        -- back, which is what we want: a half-seated batch is worse than none, and
        -- reaching this at all means the form was bypassed.
        _row_person := nullif(_row->>'person', '')::uuid;
        _row_role := nullif(_row->>'person_role', '')::uuid;
        _row_priority := null;

        if _row_person is not null then
            if _row_role is null then
                raise exception 'A named person needs a role to be seated in';
            end if;

            select r.priority into _row_priority
            from public.roles r
            where r.id = _row_role and r.venueid = _venueid;

            if _row_priority is null then
                raise exception 'That role does not belong to this venue';
            end if;

            -- Seating is not a way to hand out a role. Priority-0 holders can approve
            -- any assignment on the submission, edit its author list and mark it done,
            -- and every seat is a claim on the venue's tokens, so the person must
            -- already hold the role.
            if not exists (
                select 1
                from public.volunteers v
                where v.roleid = _row_role
                    and v.scholarid = _row_person
                    and v.active
                    and v.accepted = 'accepted'
            ) then
                raise exception 'A named person must already be an accepted, active volunteer in that role';
            end if;

            insert into public.assignments (venue, submission, scholar, role, bid, approved)
            values (_venueid, _new_submission_id, _row_person, _row_role, false, true);
            _seated := _seated + 1;
            _seated_by := jsonb_set(
                _seated_by,
                array[_row_person::text],
                to_jsonb(coalesce((_seated_by->>_row_person::text)::integer, 0) + 1)
            );
        end if;

        -- The venue's sole editor is still seated, except on a row that named
        -- somebody for the editor role itself. Doing both would put two priority-0
        -- assignments on one submission, and marking a submission done pays every
        -- approved priority-0 assignment on it -- an editor's compensation per editor
        -- per paper.
        if _editor is not null and not (_row_person is not null and _row_priority = 0) then
            insert into public.assignments (venue, submission, scholar, role, bid, approved)
            values (_venueid, _new_submission_id, _editor, _editor_role, false, true);
            _seated := _seated + 1;
            _seated_by := jsonb_set(
                _seated_by,
                array[_editor::text],
                to_jsonb(coalesce((_seated_by->>_editor::text)::integer, 0) + 1)
            );
        end if;

        -- A submission with nobody in the venue's top-priority role is waiting for an
        -- editor, and is flagged as such on the venue's submissions list. Counted per
        -- row rather than derived from _seated, which counts assignments: a row can
        -- carry two of them -- an associate editor named by the file and the venue's
        -- sole editor -- and subtracting one from the other would report nonsense.
        if not (_row_person is not null and _row_priority = 0) and _editor is null then
            _waiting := _waiting + 1;
        end if;

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
        'mint_amount', _mint_amount,
        'editor', _editor,
        'seated', _seated,
        'seated_by', _seated_by,
        'waiting', _waiting
    );
end;
$function$;
