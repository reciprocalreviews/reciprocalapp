-- Unmatched assignments and compensation claims, for importing a venue's backlog
-- before everyone named in it has an account.
--
-- 1. public.unmatched_assignments keeps the names bulk_import_submissions could not
--    match, and public.match_assignments lets whoever approves one match it to a
--    scholar once the person joins.
-- 2. public.request_compensation lets a volunteer ask to be paid for work on a
--    submission they were never assigned to, filing an unapproved CLAIM that
--    complete_assignment may approve and pay in one step and decline_bid may decline.
--
-- See supabase/schemas/unmatched_assignments.sql, assignments.sql and submissions.sql.
-- Every function re-created here has its anon EXECUTE revoked in this same file:
-- create or replace re-grants it under Supabase's default privileges.

--------------------------------------
-- 1. Unmatched assignments
-- An assignment on an imported submission whose person is not on the platform yet.
--
-- A venue's backlog names editors and reviewers who have not created accounts, and the
-- import cannot assign a person who does not exist. Before this table the import
-- assigned nobody and threw the name away, so once that person did sign up nothing
-- remembered which submissions were theirs, and an admin had to reconstruct it from the
-- original export. An unmatched assignment keeps the name exactly as the file spelled
-- it, so whoever approves that assignment can later match it to a scholar by hand
-- (public.match_assignments). It is never matched automatically: a name is not an
-- identity, and the wrong person in an editor role can approve and pay for work on the
-- paper.
create table if not exists public.unmatched_assignments (
	id uuid default gen_random_uuid() not null,
	-- The venue, denormalized from the submission for listing a venue's rows.
	venue uuid not null,
	-- The submission the assignment is on.
	submission uuid not null,
	-- The role the file named this person in.
	role uuid not null,
	-- The name as the import file spelled it.
	name text not null,
	created_at timestamp with time zone default timezone ('utc'::text, now()) not null,
	constraint unmatched_assignments_name_check check (char_length(btrim(name)) between 1 and 200),
	-- One per role per submission, the same rule bulk_import_submissions holds
	-- assignments to.
	constraint unmatched_assignments_submission_role_unique unique (submission, role)
);

alter table public.unmatched_assignments OWNER to "postgres";

alter table only public.unmatched_assignments
add constraint "unmatched_assignments_pkey" primary key (id);

alter table only public.unmatched_assignments
add constraint "unmatched_assignments_venue_fkey" foreign KEY (venue) references public.venues (id) on delete cascade;

alter table only public.unmatched_assignments
add constraint "unmatched_assignments_submission_fkey" foreign KEY (submission) references public.submissions (id) on delete cascade;

alter table only public.unmatched_assignments
add constraint "unmatched_assignments_role_fkey" foreign KEY (role) references public.roles (id) on delete cascade;

create index "unmatched_assignments_venue_index" on public.unmatched_assignments using "btree" (venue);

-- Written only by the SECURITY DEFINER RPCs below and bulk_import_submissions; clients
-- may read and dismiss, nothing else.
grant
select
,
	delete on table public.unmatched_assignments to "authenticated";

grant all on table public.unmatched_assignments to "service_role";

--------------------------------------
-- Security
alter table public.unmatched_assignments enable row level security;

-- Whoever could approve the assignment once matched may see it and dismiss it: a venue
-- admin, the submission's editor, or the holder of the approving role on it, and never
-- while conflicted on the submission. The same rule as seeing an assignment at all
-- (the assignments SELECT policy), so an associate editor sees the reviewers their own
-- submissions are missing and nothing else, and an editor-less submission's missing
-- editor is an admin's to match.
create policy "approvers can view unmatched assignments" on public.unmatched_assignments for
select
	to authenticated using (
		public.can_approve_assignment (submission, role)
		and not public.isConflicted (submission)
	);

-- A row that will never be matched -- a person who is not coming, or a name that was a
-- typo for someone already assigned -- may be dismissed by the same people.
create policy "approvers can dismiss unmatched assignments" on public.unmatched_assignments for delete to authenticated using (
	public.can_approve_assignment (submission, role)
	and not public.isConflicted (submission)
);

--------------------------------------
-- RPC
-- match_assignments: match a name from an import to a scholar, and assign them on every
-- unmatched assignment held under that name and role at the venue that the caller may
-- approve.
--
-- The scholar must already be an accepted, active volunteer in the role, the same rule
-- bulk_import_submissions holds named people to: matching is not a way to hand out a
-- role. A row is skipped, and kept, when the scholar is an author of or conflicted on
-- the submission, or when someone else already holds the role -- or, for a priority-0
-- role, any priority-0 assignment -- on it. If the scholar already has an assignment
-- there, typically a compensation claim filed before anyone could match them, it is
-- approved rather than duplicated.
--
-- Returns the submissions matched, so the client can send the scholar one digest, and
-- how many rows were skipped.
create or replace function public.match_assignments (_venue uuid, _name text, _role uuid, _scholar uuid) returns jsonb language plpgsql security definer
set
	search_path to '' as $$
declare
	_priority integer;
	_row public.unmatched_assignments;
	_existing uuid;
	_found boolean := false;
	_matched uuid[] := array[]::uuid[];
	_skipped integer := 0;
begin
	if (select auth.uid()) is null then
		raise exception 'Authentication required';
	end if;

	select r.priority into _priority
	from public.roles r
	where r.id = _role and r.venueid = _venue;

	if _priority is null then
		raise exception 'That role does not belong to this venue';
	end if;

	if not exists (
		select 1
		from public.volunteers v
		where v.roleid = _role
			and v.scholarid = _scholar
			and v.active
			and v.accepted = 'accepted'
	) then
		raise exception 'A matched person must already be an accepted, active volunteer in that role'
			using errcode = 'RR019';
	end if;

	for _row in
		select *
		from public.unmatched_assignments u
		where u.venue = _venue and u.role = _role and u.name = _name
			and public.can_approve_assignment(u.submission, u.role)
			and not public.isConflicted(u.submission)
		order by u.created_at
		for update
	loop
		_found := true;

		if exists (
			select 1 from public.submissions s
			where s.id = _row.submission and _scholar = any (s.authors)
		)
		or exists (
			select 1 from public.conflicts c
			where c.submissionid = _row.submission and c.scholarid = _scholar
		)
		or exists (
			select 1
			from public.assignments a
			join public.roles r on r.id = a.role
			where a.submission = _row.submission
				and a.approved
				and a.scholar <> _scholar
				and (a.role = _role or (_priority = 0 and r.priority = 0))
		) then
			_skipped := _skipped + 1;
			continue;
		end if;

		select a.id into _existing
		from public.assignments a
		where a.submission = _row.submission and a.role = _role and a.scholar = _scholar
		limit 1;

		if found then
			update public.assignments set approved = true where id = _existing;
		else
			insert into public.assignments (venue, submission, scholar, role, bid, approved)
			values (_venue, _row.submission, _scholar, _role, false, true);
		end if;

		delete from public.unmatched_assignments where id = _row.id;
		_matched := _matched || _row.submission;
	end loop;

	if not _found then
		raise exception 'You cannot match any assignments under that name and role';
	end if;

	return jsonb_build_object('matched', to_jsonb(_matched), 'skipped', _skipped);
end;
$$;

alter function public.match_assignments (uuid, text, uuid, uuid) OWNER to "postgres";

revoke
execute on function public.match_assignments (uuid, text, uuid, uuid)
from
	public,
	anon;

grant
execute on function public.match_assignments (uuid, text, uuid, uuid) to authenticated;

create or replace trigger unmatched_assignments_audit
after insert
or
update
or delete on public.unmatched_assignments for each row
execute function public.log_audit_event ();

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
    _row_editor_seated boolean;
    _entry_name text;
    _unmatched integer := 0;
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
        _row_editor_seated := false;

        if jsonb_typeof(coalesce(_row->'people', '[]'::jsonb)) <> 'array' then
            raise exception 'A row''s people must be a list of person and role pairs';
        end if;

        for _entry in select * from jsonb_array_elements(coalesce(_row->'people', '[]'::jsonb))
        loop
            _entry_person := nullif(_entry->>'person', '')::uuid;
            _entry_role := nullif(_entry->>'person_role', '')::uuid;
            _entry_name := nullif(btrim(coalesce(_entry->>'name', '')), '');

            -- A blank cell in one role's column says nothing about the other roles on
            -- the same row, so it is skipped rather than refused.
            continue when _entry_person is null and _entry_name is null;

            if _entry_person is not null and _entry_name is not null then
                raise exception 'An entry names either a scholar or an unmatched name, not both';
            end if;

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

            -- A name the platform does not know yet is kept as an unmatched assignment
            -- rather than thrown away, so whoever approves it can match it once the person
            -- joins (public.match_assignments). It still occupies the role for the two
            -- checks above, and an unmatched editor still suppresses the sole-editor
            -- fallback below -- the file says someone else edits this paper -- but it does
            -- not count as assigned: nobody can act on the submission yet, so it is still
            -- waiting for an editor.
            if _entry_person is null then
                insert into public.unmatched_assignments (venue, submission, role, name)
                values (_venueid, _new_submission_id, _entry_role, _entry_name);

                _row_roles := _row_roles || _entry_role;
                if _entry_priority = 0 then
                    _row_priority_zero := true;
                end if;

                _unmatched := _unmatched + 1;
                continue;
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
                _row_editor_seated := true;
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
            _row_editor_seated := true;
        end if;

        -- A submission with nobody in the venue's top-priority role is waiting for an
        -- editor, and is flagged as such on the venue's submissions list. Counted per
        -- row rather than derived from _seated, which counts assignments: a row can
        -- carry two of them -- an associate editor named by the file and the venue's
        -- sole editor -- and subtracting one from the other would report nonsense.
        if not _row_editor_seated then
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
        'unmatched', _unmatched,
        'skipped', _skipped
    );
end;
$function$;

alter function public.bulk_import_submissions (uuid, jsonb, text) OWNER to "postgres";

revoke
execute on function public.bulk_import_submissions (uuid, jsonb, text)
from
	public,
	anon;

grant
execute on function public.bulk_import_submissions (uuid, jsonb, text) to authenticated;

--------------------------------------
-- 2. Compensation claims
alter table public.assignments
drop constraint assignments_decline_only_bids_check;

alter table public.assignments
add constraint assignments_decline_only_bids_check check (
	declined_at is null
	or (
		(
			bid
			or compensation_requested_at is not null
		)
		and not approved
		and not completed
	)
);

create or replace function public.decline_bid (_assignment uuid, _reason text) returns jsonb language plpgsql security definer
set
	search_path to '' as $$
declare
	_caller uuid;
	_a public.assignments;
	_trimmed text;
begin
	_caller := (select auth.uid());
	if _caller is null then
		raise exception 'Authentication required';
	end if;

	select * into _a from public.assignments where id = _assignment for update;
	if not found then
		raise exception 'Bid not found';
	end if;

	if not public.can_approve_assignment(_a.submission, _a.role)
		or public.isConflicted(_a.submission) then
		raise exception 'You are not authorized to decline this bid';
	end if;

	-- A pending claim (see compensation_requested_at) is answered the same way: it is
	-- also somebody asking an approver for something, and a no needs a reason.
	if not (_a.bid or _a.compensation_requested_at is not null)
		or _a.approved or _a.completed or _a.declined_at is not null then
		raise exception 'This bid is no longer pending' using errcode = 'RR017';
	end if;

	_trimmed := btrim(coalesce(_reason, ''));
	if char_length(_trimmed) = 0 then
		raise exception 'A declined bid needs an explanation for the bidder';
	end if;
	if char_length(_trimmed) > 1000 then
		raise exception 'An explanation must be at most 1000 characters';
	end if;

	update public.assignments
	set declined_at = now(), declined_by = _caller, decline_reason = _trimmed
	where id = _assignment;

	return jsonb_build_object(
		'venue', _a.venue,
		'submission', _a.submission,
		'scholar', _a.scholar,
		'role', _a.role
	);
end;
$$;

alter function public.decline_bid (uuid, text) OWNER to "postgres";

revoke
execute on function public.decline_bid (uuid, text)
from
	public,
	anon;

grant
execute on function public.decline_bid (uuid, text) to authenticated;

create or replace function public.request_compensation (_venue uuid, _externalid text, _role uuid) returns jsonb language plpgsql security definer
set
	search_path to '' as $$
declare
	_caller uuid;
	_submission uuid;
	_priority integer;
	_a public.assignments;
	_recipients uuid[];
begin
	_caller := (select auth.uid());
	if _caller is null then
		raise exception 'Authentication required';
	end if;

	select s.id into _submission
	from public.submissions s
	where s.venue = _venue and s.externalid = btrim(coalesce(_externalid, ''));
	if _submission is null then
		raise exception 'No submission with that manuscript ID at this venue'
			using errcode = 'RR020';
	end if;

	select r.priority into _priority
	from public.roles r
	where r.id = _role and r.venueid = _venue;
	if _priority is null then
		raise exception 'That role does not belong to this venue';
	end if;

	select * into _a
	from public.assignments a
	where a.submission = _submission and a.role = _role and a.scholar = _caller
	limit 1
	for update;

	if found then
		if _a.completed then
			raise exception 'This work has already been compensated' using errcode = 'RR021';
		end if;
		if _a.declined_at is not null then
			raise exception 'This request was declined' using errcode = 'RR022';
		end if;
		update public.assignments
		set compensation_requested_at = coalesce(compensation_requested_at, now())
		where id = _a.id;
	else
		if _priority = 0 then
			raise exception 'Editors are compensated by marking a submission done'
				using errcode = 'RR023';
		end if;

		if not exists (
			select 1
			from public.volunteers v
			where v.roleid = _role
				and v.scholarid = _caller
				and v.accepted = 'accepted'
		) then
			raise exception 'Only volunteers in this role can request compensation for it'
				using errcode = 'RR024';
		end if;

		if exists (
			select 1 from public.submissions s
			where s.id = _submission and _caller = any (s.authors)
		) then
			raise exception 'Authors cannot request compensation for their own submission'
				using errcode = 'RR024';
		end if;

		insert into public.assignments (venue, submission, scholar, role, bid, approved, compensation_requested_at)
		values (_venue, _submission, _caller, _role, false, false, now());
	end if;

	select coalesce(array_agg(distinct x.scholar), array[]::uuid[]) into _recipients
	from (
		select a.scholar
		from public.assignments a
		join public.roles target on target.id = _role
		where a.submission = _submission and a.approved and a.role = target.approver
		union
		select a.scholar
		from public.assignments a
		join public.roles r on r.id = a.role
		where a.submission = _submission and a.approved and r.priority = 0
		union
		select unnest(v.admins)
		from public.venues v
		where v.id = _venue
	) x
	where x.scholar <> _caller
		and not exists (
			select 1 from public.conflicts c
			where c.submissionid = _submission and c.scholarid = x.scholar
		);

	return jsonb_build_object('submission', _submission, 'recipients', to_jsonb(_recipients));
end;
$$;

alter function public.request_compensation (uuid, text, uuid) OWNER to "postgres";

revoke
execute on function public.request_compensation (uuid, text, uuid)
from
	public,
	anon;

grant
execute on function public.request_compensation (uuid, text, uuid) to authenticated;

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
    -- A claim is the one unapproved assignment that may be completed: the scholar has
    -- said the work is done, so approving it and paying for it are one decision, and the
    -- update below records both. That includes a declined claim, which is how an approver
    -- changes their mind -- approving clears the decline (enforce_assignment_updates).
    if not _assignment.approved and _assignment.compensation_requested_at is null then
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

    -- Mark the assignment completed, approving a claim along the way.
    update public.assignments set approved = true, completed = true where id = _assignment_id;

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

alter function public.complete_assignment (uuid, text, text) OWNER to "postgres";

revoke
execute on function public.complete_assignment (uuid, text, text)
from
	public,
	anon;

grant
execute on function public.complete_assignment (uuid, text, text) to authenticated;
