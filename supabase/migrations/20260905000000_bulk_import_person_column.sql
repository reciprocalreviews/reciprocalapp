-- Let a bulk import name the people to seat on each submission, one per venue role.
--
-- WHY
--
-- An import could seat an editor only when the venue had exactly one accepted,
-- active volunteer in its top-priority role (20260828040000). That rule is right for
-- what it does -- with several editors the choice would be arbitrary -- but it leaves
-- every venue that has more than one editor importing a whole backlog with nobody on
-- it, which is the case a backlog import is usually for. Exports name a handling
-- editor per manuscript; the information was there and we were throwing it away.
--
-- ONE COLUMN PER ROLE
--
-- The role is chosen per import rather than fixed at priority 0, because venues are
-- not shaped alike: one venue's per-paper editor column names its associate editors
-- while another's names the holders of its top role. Fixing it at priority 0 would
-- have made the column useless to the first kind of venue and would have quietly
-- handed out editorial authority at the second.
--
-- And a file may name several: an export commonly carries both an "Editor in Chief"
-- column and an "Editor" column, which are two different people in two different
-- roles on the same manuscript. So the form offers one column per role and a row
-- carries a list. Which of a file's columns corresponds to which of a venue's roles
-- is venue semantics and nothing guesses it -- matching on the role's own name would
-- map that example exactly the wrong way round, in the direction that hands out the
-- priority-0 seat.
--
-- WHY A LIST RATHER THAN A ROLE-KEYED OBJECT
--
-- `{"<role>": "<scholar>"}` would make a duplicate role unrepresentable, which sounds
-- better than it is: jsonb silently de-duplicates object keys with last-value-wins, so
-- a caller sending two entries for one role would have one of them chosen arbitrarily
-- and nothing would say so. A list makes malformed input visible and refusable, which
-- is the same argument as the one below about form-only rules.
--
-- WHAT IS CHECKED HERE, AND WHY HERE
--
-- The client resolves each written name to a scholar id against the venue's own
-- volunteers and refuses to submit a row it could not resolve. This function checks
-- the same things again -- that the role belongs to the venue, and that the scholar
-- already holds it, accepted and active -- because a rule that lives only in a form is
-- a rule that holds only for people who use the form, which is the same reason
-- create_submission re-checks its own charges (RR007/RR008). Without it, a bulk import
-- would be an API-level way for a venue admin to grant a priority-0 seat: approve any
-- assignment on the submission, edit its author list, mark it done, and be paid for it
-- by mark_submission_done.
--
-- A failed check raises, which rolls the entire import back -- including assignments
-- an earlier entry on the same row already inserted. That is deliberate: a partially
-- seated batch is harder to reason about than no batch, and since the client already
-- blocked this case, arriving here means the form was bypassed.
--
-- AT MOST ONE PRIORITY-0 SEAT PER ROW
--
-- Two guards, because there are now two ways to get a second one. Within a row, a
-- second entry whose role is priority 0 is refused. Across the row, the sole-editor
-- fallback stands down whenever any entry already took a priority-0 seat. Seating both
-- would put two priority-0 assignments on one submission, and marking a submission
-- done pays every approved priority-0 assignment on it -- an editor's compensation per
-- editor per paper, which is the reason the original rule refused to choose among
-- several editors at all.
--
-- The rule is stated by priority rather than by role identity because roles.priority
-- has no per-venue uniqueness constraint -- the sole-editor lookup below already hedges
-- with `order by r.id limit 1` -- and one menu per role means two priority-0 columns
-- are something an admin can actually produce.
--
-- Seating a role below priority 0 has a different and intended consequence: that
-- assignment blocks mark_submission_done until it has been compensated, and is paid
-- from the venue reserve at the (submission type, role) rate. Note that the import's
-- mint is sized only by submission type cost while a row may now seat several paid
-- assignments. DESIGN.md:434 states that a type's cost must equal the compensation
-- paid out for it, but that is a design rule an admin follows, not a constraint
-- anything enforces -- there is none in compensation.sql -- so a venue that sets those
-- amounts inconsistently can still under-fund its own reserve here.
--
-- THE SIGNATURE DOES NOT CHANGE
--
-- The people ride in the per-row jsonb rather than as new arguments, and the list is
-- ordinary nesting inside the same `_submissions` value. `create or replace` on an
-- unchanged signature keeps the function's OID, and with it the `grant execute to
-- authenticated` that 20260831000000 attached -- so there is no drop, no re-grant, and
-- no change to the generated client types. A new parameter with a default would have
-- been worse than one without: Postgres would have created a second overload, left the
-- old one in place and granted, and made PostgREST's resolution ambiguous.
--
-- ON RLS
--
-- The assignments insert bypasses the assignments INSERT policy because this function
-- is SECURITY DEFINER. It grants no authority the caller did not have: the caller was
-- already required to be a venue admin above, and that policy admits an admin of the
-- venue anyway.
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
    _entry jsonb;
    _entry_person uuid;
    _entry_role uuid;
    _entry_priority integer;
    _row_roles uuid[];
    _row_priority_zero boolean;
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

        -- A row may name one person per venue role. An export carrying both an
        -- "Editor in Chief" column and an "Editor" column names two different people
        -- in two different roles on the same manuscript, and reading only one of them
        -- throws the other away. The client resolves each name against the venue's own
        -- volunteers and refuses to submit a row it could not; every entry is checked
        -- again here because a rule that lives only in the form is a rule that holds
        -- only for people who use the form -- the same reason create_submission
        -- re-checks its own charges. Any raise below rolls the whole import back,
        -- including submissions and assignments earlier rows already wrote: a
        -- half-seated batch is worse than none, and reaching this means the form was
        -- bypassed.
        --
        -- The submission is inserted above, before these checks run. That is fine and
        -- deliberate -- a raise anywhere aborts the transaction -- so there is nothing
        -- to gain by hoisting the validation.
        --
        -- RESET PER ROW. These two carry the per-submission guarantees below, and
        -- `declare` runs once per call, not once per row. Leaking either would let the
        -- first row's editor suppress the fallback for every row after it, silently:
        -- right submission count, right mint, no error, and nothing else holding an
        -- editor.
        _row_roles := array[]::uuid[];
        _row_priority_zero := false;

        if jsonb_typeof(coalesce(_row->'people', '[]'::jsonb)) <> 'array' then
            raise exception 'A row''s people must be a list of person and role pairs';
        end if;

        for _entry in select * from jsonb_array_elements(coalesce(_row->'people', '[]'::jsonb))
        loop
            _entry_person := nullif(_entry->>'person', '')::uuid;
            _entry_role := nullif(_entry->>'person_role', '')::uuid;

            -- A blank cell in one role's column says nothing about the other roles on
            -- the same row, so it is skipped rather than refused.
            continue when _entry_person is null;

            if _entry_role is null then
                raise exception 'A named person needs a role to be seated in';
            end if;

            select r.priority into _entry_priority
            from public.roles r
            where r.id = _entry_role and r.venueid = _venueid;

            if _entry_priority is null then
                raise exception 'That role does not belong to this venue';
            end if;

            -- One seat per role per submission. The form offers each role exactly one
            -- column, so two of them cannot target the same role; nothing outside the
            -- form is bound by that, and two assignments in one role are two claims on
            -- the venue's reserve for one piece of work. Refused rather than
            -- de-duplicated, so a caller cannot decide which of the two survives.
            if _entry_role = any(_row_roles) then
                raise exception 'A submission cannot seat two people in the same role';
            end if;

            -- At most one priority-0 seat per submission -- stated by PRIORITY, not by
            -- role identity. mark_submission_done pays every approved priority-0
            -- assignment on a submission, so a second one is a second editor's fee for
            -- one paper. roles.priority carries no per-venue uniqueness constraint,
            -- which is why the sole-editor lookup above already says `order by r.id
            -- limit 1`; two distinct priority-0 roles would be two distinct columns in
            -- the form, and checking the priority is what covers that.
            if _entry_priority = 0 and _row_priority_zero then
                raise exception 'A submission can have only one editor';
            end if;

            -- Seating is not a way to hand out a role. Priority-0 holders can approve
            -- any assignment on the submission, edit its author list and mark it done,
            -- and every seat is a claim on the venue's tokens, so the person must
            -- already hold the role.
            if not exists (
                select 1
                from public.volunteers v
                where v.roleid = _entry_role
                    and v.scholarid = _entry_person
                    and v.active
                    and v.accepted = 'accepted'
            ) then
                raise exception 'A named person must already be an accepted, active volunteer in that role';
            end if;

            insert into public.assignments (venue, submission, scholar, role, bid, approved)
            values (_venueid, _new_submission_id, _entry_person, _entry_role, false, true);

            _row_roles := _row_roles || _entry_role;
            if _entry_priority = 0 then
                _row_priority_zero := true;
            end if;

            _seated := _seated + 1;
            _seated_by := jsonb_set(
                _seated_by,
                array[_entry_person::text],
                to_jsonb(coalesce((_seated_by->>_entry_person::text)::integer, 0) + 1)
            );
        end loop;

        -- The venue's sole editor is still seated, except on a row that named
        -- somebody for the editor role itself. Doing both would put two priority-0
        -- assignments on one submission, and marking a submission done pays every
        -- approved priority-0 assignment on it -- an editor's compensation per editor
        -- per paper.
        if _editor is not null and not _row_priority_zero then
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
        if not _row_priority_zero and _editor is null then
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
