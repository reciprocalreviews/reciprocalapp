-- Assign from a list: public.assign_submissions seats people on submissions the venue already
-- has, from a pasted list of manuscript IDs and names. See supabase/schemas/unmatched_assignments.sql.

create or replace function public.assign_submissions (
	_venue uuid,
	_role uuid,
	_rows jsonb,
	_dry_run boolean
) returns jsonb language plpgsql security definer
set
	search_path to '' as $$
declare
	_caller uuid := (select auth.uid());
	_priority integer;
	_row jsonb;
	_externalid text;
	_person uuid;
	_name text;
	_submission public.submissions;
	_holder uuid;
	_existing uuid;
	_verdict text;
	_seen text[] := array[]::text[];
	_results jsonb := '[]'::jsonb;
	_seated_by jsonb := '{}'::jsonb;
	_seated integer := 0;
	_kept integer := 0;
	_skipped integer := 0;
begin
	if _caller is null then
		raise exception 'Authentication required';
	end if;

	-- The same people who may bulk import: they are the ones managing a backlog.
	if not (public.isAdmin(_venue) or public.isPriorityZero(_venue)) then
		raise exception 'Only venue admins and editors can assign from a list'
			using errcode = '42501';
	end if;

	select r.priority into _priority
	from public.roles r
	where r.id = _role and r.venueid = _venue;

	if _priority is null then
		raise exception 'That role does not belong to this venue';
	end if;

	if jsonb_typeof(_rows) is distinct from 'array' or jsonb_array_length(_rows) = 0 then
		raise exception 'No rows provided';
	end if;

	for _row in select * from jsonb_array_elements(_rows)
	loop
		_externalid := btrim(coalesce(_row->>'externalid', ''));
		_person := nullif(_row->>'person', '')::uuid;
		_name := nullif(btrim(coalesce(_row->>'name', '')), '');
		_holder := null;
		_verdict := null;

		if (_person is null) = (_name is null) then
			raise exception 'A row names either a scholar or an unmatched name';
		end if;

		-- Locked, so two people working the same list cannot both seat one paper.
		select s.* into _submission
		from public.submissions s
		where s.venue = _venue and s.externalid = _externalid
		for update;

		if not found then
			_verdict := 'missing';
		elsif _externalid = any(_seen) then
			_verdict := 'duplicate';
		elsif _submission.status <> 'reviewing' then
			_verdict := 'done';
		elsif _caller = any(_submission.authors) or public.isConflicted(_submission.id) then
			_verdict := 'recused';
		elsif _person is not null and not exists (
			select 1 from public.volunteers v
			where v.roleid = _role and v.scholarid = _person and v.active and v.accepted = 'accepted'
		) then
			_verdict := 'not_volunteer';
		elsif _person = any(_submission.authors) then
			_verdict := 'author';
		elsif _person is not null and exists (
			select 1 from public.conflicts c
			where c.submissionid = _submission.id and c.scholarid = _person
		) then
			_verdict := 'conflicted';
		elsif _person is not null and exists (
			select 1 from public.assignments a
			where a.submission = _submission.id and a.role = _role and a.scholar = _person
				and a.approved
		) then
			_verdict := 'already';
		else
			-- One seat per role, and one priority-0 seat per submission, since marking a
			-- submission done pays every approved priority-0 assignment on it.
			select a.scholar into _holder
			from public.assignments a
			join public.roles r on r.id = a.role
			where a.submission = _submission.id
				and a.approved
				and a.scholar is distinct from _person
				and (a.role = _role or (_priority = 0 and r.priority = 0))
			order by a.id
			limit 1;

			if _holder is not null then
				_verdict := 'held';
			elsif exists (
				select 1 from public.unmatched_assignments u
				where u.submission = _submission.id and u.role = _role
			) then
				_verdict := 'waiting';
			elsif _person is not null then
				_verdict := 'ready';
			else
				_verdict := 'keep';
			end if;
		end if;

		if _verdict <> 'missing' then
			_seen := _seen || _externalid;
		end if;

		if not _dry_run then
			if _verdict = 'ready' then
				-- A bid or claim by the same person becomes their approved assignment
				-- rather than a duplicate beside it, as match_assignments does.
				select a.id into _existing
				from public.assignments a
				where a.submission = _submission.id and a.role = _role and a.scholar = _person
				order by a.id
				limit 1;

				if _existing is not null then
					update public.assignments set approved = true where id = _existing;
				else
					insert into public.assignments (venue, submission, scholar, role, bid, approved)
					values (_venue, _submission.id, _person, _role, false, true);
				end if;

				_seated_by := jsonb_set(
					_seated_by,
					array[_person::text],
					to_jsonb(coalesce((_seated_by->>_person::text)::integer, 0) + 1)
				);
				_seated := _seated + 1;
				_verdict := 'seated';
			elsif _verdict = 'keep' then
				insert into public.unmatched_assignments (venue, submission, role, name)
				values (_venue, _submission.id, _role, _name);
				_kept := _kept + 1;
				_verdict := 'kept';
			else
				_skipped := _skipped + 1;
			end if;
		end if;

		_results := _results || jsonb_build_object(
			'externalid', _externalid,
			'submission', case when _verdict = 'missing' then null else _submission.id end,
			'title', case when _verdict = 'missing' then null else _submission.title end,
			'verdict', _verdict,
			'holder', _holder
		);
	end loop;

	return jsonb_build_object(
		'rows', _results,
		'seated', _seated,
		'seated_by', _seated_by,
		'kept', _kept,
		'skipped', _skipped
	);
end;
$$;

alter function public.assign_submissions (uuid, uuid, jsonb, boolean) OWNER to "postgres";

revoke
execute on function public.assign_submissions (uuid, uuid, jsonb, boolean)
from
	public,
	anon;

grant
execute on function public.assign_submissions (uuid, uuid, jsonb, boolean) to authenticated;
