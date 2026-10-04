--------------------------------------
-- Schema
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
create or replace function public.match_assignments (
	_venue uuid,
	_name text,
	_role uuid,
	_scholar uuid
) returns jsonb language plpgsql security definer
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
