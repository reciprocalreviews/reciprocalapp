-- The digest a bulk import sends told everyone it seated that they were the venue's
-- editor, and that they had been assigned automatically because they were its ONLY
-- editor. Both are things the message cannot know: the import file names one person
-- per venue role per row, so most recipients hold some other role, and most were named
-- in the file rather than seated by the sole-editor fallback. See #181.
--
-- The prose is fixed in supabase/functions/_shared/templates.ts. What is fixed HERE is
-- the number that message carries. seated_by counted assignment ROWS, and the two
-- seating paths are independently reachable on one row -- the venue's sole editor, also
-- named in the file for some other role, takes both seats -- so the digest could say
-- two submissions had arrived when one had. It is now derived once from the rows the
-- import wrote, counting distinct submissions. That is the same hazard _waiting already
-- guards against by counting per row rather than subtracting one number from another.
--
-- The `revoke execute ... from anon` below travels in THIS migration on purpose:
-- Supabase's default privileges re-grant EXECUTE to anon every time a function is
-- created, so a revoke left behind in an earlier migration is undone by this one.
-- supabase/tests/rls/definer_grants.sql check 1 is what catches it if this is ever
-- forgotten.

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
    _skipped integer := 0;
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
        ) on conflict (venue, externalid) do nothing
        returning id into _new_submission_id;

        -- Already at this venue: skip the row and carry on with the batch.
        --
        -- An export of a venue's queue is exported again next month still carrying last
        -- month's manuscripts, so an overlap with what is already here is the ordinary
        -- shape of this feature's input rather than a mistake in the file. Without this,
        -- submissions_venue_externalid_unique raised 23505 and rolled the whole import
        -- back, and the only way to import the new rows was to delete the old ones from
        -- the file by hand. The form flags these rows before submitting and leaves them
        -- out; this clause is what makes a list of existing IDs that has gone stale --
        -- the page left open while somebody else imported -- cost those rows and nothing
        -- else.
        --
        -- Targeted at (venue, externalid) rather than a bare `do nothing`, so any other
        -- unique violation is still an error rather than a submission that silently
        -- vanishes from the batch.
        --
        -- `continue` lands ahead of the people loop, the sole-editor fallback, the
        -- waiting count and the mint: a row that was not written seats nobody, is not
        -- waiting for an editor, and funds nothing.
        if not found then
            _skipped := _skipped + 1;
            continue;
        end if;

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

    -- Who now holds what, counted by DISTINCT SUBMISSION rather than by assignment.
    -- The digest this feeds tells a scholar how many submissions they were given, and
    -- the two seating paths above are independently reachable on one row: the venue's
    -- sole editor, also named in the file for some other role, takes both seats and
    -- would otherwise be told two papers arrived when one did. That is the same hazard
    -- _waiting states above, which is why it is counted per row rather than derived
    -- from _seated. Derived here, after the loop, rather than incremented inside it:
    -- the rows are the answer, and counting them twice in two places is how the two
    -- numbers came to disagree.
    select coalesce(jsonb_object_agg(x.scholar::text, x.submissions), '{}'::jsonb)
        into _seated_by
    from (
        select a.scholar, count(distinct a.submission) as submissions
        from public.assignments a
        where a.submission = any(_submission_ids)
        group by a.scholar
    ) x;

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
        'waiting', _waiting,
        'skipped', _skipped
    );
end;
$function$;

revoke execute on function public.bulk_import_submissions (uuid, jsonb, text)
from
	public,
	anon,
	authenticated;

grant execute on function public.bulk_import_submissions (uuid, jsonb, text) to authenticated;
