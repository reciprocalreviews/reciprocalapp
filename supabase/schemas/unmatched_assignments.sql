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
--
-- Holders of the venue's top role see every row as admins do. A backlog usually arrives
-- with no editor seated on it, so the per-submission branch alone left a venue's
-- editor-in-chief who was not also an admin unable to see the names they were asked to
-- staff.
create policy "approvers can view unmatched assignments" on public.unmatched_assignments for
select
	to authenticated using (
		(
			public.can_approve_assignment (submission, role)
			or public.isPriorityZero (venue)
		)
		and not public.isConflicted (submission)
	);

-- A row that will never be matched -- a person who is not coming, or a name that was a
-- typo for someone already assigned -- may be dismissed by the same people.
create policy "approvers can dismiss unmatched assignments" on public.unmatched_assignments for delete to authenticated using (
	(
		public.can_approve_assignment (submission, role)
		or public.isPriorityZero (venue)
	)
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
			and (public.can_approve_assignment(u.submission, u.role) or public.isPriorityZero(u.venue))
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

--------------------------------------
-- person_name_key: a name reduced to comparable words, the SQL twin of nameTokens in
-- src/lib/data/matchPersonName.ts. Accents stripped, lowercased, split on anything that is
-- not a letter or digit, and the words sorted, so "Petersen, Andrew" and "Andrew Petersen"
-- produce the same key. Keep the two in step: a name the import would call the same person
-- must be one this calls the same person, or the notice below fires for a different set of
-- names than the matching page suggests.
create or replace function public.person_name_key (_name text) returns text language sql immutable
set
	search_path to '' as $$
	select coalesce(string_agg(w, ' ' order by w), '')
	from regexp_split_to_table(
		lower(regexp_replace(normalize(coalesce(_name, ''), NFD), '[̀-ͯ]', '', 'g')),
		'[^a-z0-9]+'
	) as w
	where w <> '';
$$;

alter function public.person_name_key (text) OWNER to "postgres";

--------------------------------------
-- _notify_unmatched_name_joined: tell whoever could match an unmatched assignment that a
-- scholar with that name now has an account.
--
-- Before this, an import naming people who had not joined left the venue waiting on them to
-- join AND to say so: nothing noticed the account appear, so an editor learned about it
-- from the person, if at all. This only says that a name matches. It never matches anything
-- itself (a name is not an identity; see the table comment above), and it reads the same
-- "same words, any order" rule the import uses, never anything fuzzier, since a notice
-- about the wrong person costs an editor's attention every time.
--
-- Recipients are whoever could match the row, computed for every scholar rather than the
-- caller: the three branches of can_approve_assignment (the venue's admins, the
-- submission's approved priority-0 editor, and the approved holder of the role's approving
-- role on it), plus the venue's top-role holders, who see every row at the venue. Never anyone conflicted on the submission, who cannot see
-- the row, and never the scholar themselves. One email per recipient per venue, listing
-- each matching name and role with how many submissions it is on.
--
-- Owner-only: a step of the trigger below, not an entry point.
create or replace function public._notify_unmatched_name_joined (_scholar uuid) returns integer language plpgsql security definer
set
	search_path to '' as $$
declare
	_key text;
	_name text;
	_sent integer := 0;
begin
	select public.person_name_key(s.name), coalesce(nullif(btrim(s.name), ''), 'A scholar')
	into _key, _name
	from public.scholars s
	where s.id = _scholar;

	if _key is null or _key = '' then
		return 0;
	end if;

	with matched as (
		select u.venue, u.submission, u.role, u.name
		from public.unmatched_assignments u
		where public.person_name_key(u.name) = _key
	),
	approvers as (
		select m.venue, m.submission, m.role, m.name, a.admin as recipient
		from matched m
		join public.venues v on v.id = m.venue
		cross join unnest(v.admins) as a (admin)
		union
		select m.venue, m.submission, m.role, m.name, x.scholar
		from matched m
		join public.assignments x on x.submission = m.submission and x.approved
		join public.roles r on r.id = x.role and r.priority = 0
		union
		select m.venue, m.submission, m.role, m.name, x.scholar
		from matched m
		join public.roles t on t.id = m.role
		join public.assignments x on x.submission = m.submission and x.approved and x.role = t.approver
		union
		-- The venue's top-role holders, who see every unmatched row there.
		select m.venue, m.submission, m.role, m.name, x.scholarid
		from matched m
		join public.roles r on r.venueid = m.venue and r.priority = 0
		join public.volunteers x on x.roleid = r.id and x.active and x.accepted = 'accepted'
	),
	summary as (
		select ap.recipient, ap.venue, ap.role, ap.name, count(distinct ap.submission) as n
		from approvers ap
		where ap.recipient <> _scholar
			and not exists (
				select 1 from public.conflicts c
				where c.submissionid = ap.submission and c.scholarid = ap.recipient
			)
		group by ap.recipient, ap.venue, ap.role, ap.name
	),
	per_venue as (
		select
			s.recipient,
			s.venue,
			string_agg(
				format(
					'%s as %s (%s)',
					s.name,
					coalesce(nullif(btrim(r.name), ''), 'volunteer'),
					case when s.n = 1 then '1 submission' else s.n || ' submissions' end
				),
				'; ' order by r.priority, s.name
			) as lines
		from summary s
		join public.roles r on r.id = s.role
		group by s.recipient, s.venue
	)
	insert into public.emails (event, scholar, sender, venue, email, subject, message, args)
	select
		'UnmatchedNameJoined',
		sc.id,
		-- Unattributed: the scholar did not send this, they only set their name, and
		-- attributing it would let them read who the venue's approvers are.
		null,
		p.venue,
		sc.email,
		null,
		null,
		-- Every element non-null, for the reason _notify_new_volunteer gives.
		jsonb_build_array(
			_name,
			coalesce(nullif(btrim(v.title), ''), 'a venue'),
			coalesce(v.slug, v.id::text),
			_scholar::text,
			p.lines
		)
	from per_venue p
	join public.scholars sc on sc.id = p.recipient
	join public.venues v on v.id = p.venue
	where sc.email is not null
		and public.notification_allowed(sc.id, 'UnmatchedNameJoined');

	get diagnostics _sent = row_count;
	return _sent;
end;
$$;

alter function public._notify_unmatched_name_joined (uuid) OWNER to "postgres";

revoke
execute on function public._notify_unmatched_name_joined (uuid)
from
	public,
	anon,
	authenticated;

-- Fires when a scholar gets a name or changes it to a different set of words. Most people
-- sign up by email and have no name until they set one on their profile, so watching only
-- signup would miss nearly everyone. Best effort: saving a name must never fail because a
-- notice could not be composed.
create or replace function public.notify_unmatched_name_joined () returns trigger language plpgsql security definer
set
	search_path to '' as $$
begin
	if tg_op = 'INSERT'
		or public.person_name_key(old.name) is distinct from public.person_name_key(new.name) then
		begin
			perform public._notify_unmatched_name_joined(new.id);
		exception when others then
			raise warning 'notify_unmatched_name_joined: scholar % was saved but approvers could not be notified: % (%)',
				new.id, sqlerrm, sqlstate;
		end;
	end if;
	return null;
end;
$$;

alter function public.notify_unmatched_name_joined () OWNER to "postgres";

revoke
execute on function public.notify_unmatched_name_joined ()
from
	public,
	anon,
	authenticated;

create or replace trigger notify_unmatched_name_joined_on_scholar
after insert or update of name on public.scholars for each row
execute function public.notify_unmatched_name_joined ();

--------------------------------------
-- add_to_role_and_match: whoever staffs the role (see can_staff_role), having confirmed the
-- scholar agreed to it, seats them in it and matches them to the name in one step.
--
-- match_assignments requires an accepted volunteer, which used to mean inviting the person
-- and waiting for them to accept before anything could be matched. Whoever staffs a role may
-- already seat someone directly (create_volunteer with _accepted), and the interface asks them to
-- confirm the person agreed before calling this, so the two steps become one transaction:
-- nobody ends up in a role with nothing matched, or matched with no role.
--
-- An existing record is reused rather than duplicated: an unanswered invitation becomes an
-- acceptance, since agreeing is what the caller is confirming, and a paused one is resumed.
-- A declined invitation is refused (RR027). The person said no on the platform, and an
-- admin's word that they agreed elsewhere should not silently override that.
create or replace function public.add_to_role_and_match (
	_venue uuid,
	_name text,
	_role uuid,
	_scholar uuid
) returns jsonb language plpgsql security definer
set
	search_path to '' as $$
declare
	_caller uuid := (select auth.uid());
	_v public.volunteers;
	_total integer;
begin
	if _caller is null then
		raise exception 'Authentication required';
	end if;

	if not exists (select 1 from public.roles r where r.id = _role and r.venueid = _venue) then
		raise exception 'That role does not belong to this venue';
	end if;

	if not public.can_staff_role(_role) then
		raise exception 'Only those who approve this role may add someone to it';
	end if;

	select * into _v from public.volunteers where scholarid = _scholar and roleid = _role;

	if not found then
		-- Seats, grants any welcome tokens, and emails RoleEnrolled.
		perform public.create_volunteer(_scholar, _role, true, true, null);
	elsif _v.accepted = 'declined' then
		raise exception 'They declined this role, so they cannot be added to it'
			using errcode = 'RR027';
	elsif _v.accepted = 'invited' or not _v.active then
		update public.volunteers set accepted = 'accepted', active = true where id = _v.id;

		-- Accepting a first invitation at this venue earns its welcome grant, as it would
		-- have through accept_role_invite.
		if _v.accepted = 'invited' then
			select count(*) into _total
			from public.volunteers v
			join public.roles r on r.id = v.roleid
			where v.scholarid = _scholar and r.venueid = _venue;
			if _total = 1 then
				perform public._welcome_volunteer(_caller, _scholar, _role, 'Welcome tokens for joining a role');
			end if;
		end if;

		-- Told as create_volunteer tells anyone seated directly. Best effort.
		begin
			insert into public.emails (event, scholar, sender, venue, email, subject, message, args)
			select
				'RoleEnrolled', s.id, _caller, _venue, s.email, null, null,
				to_jsonb(array[r.name, v.title, coalesce(v.slug, v.id::text), s.id::text])
			from public.scholars s, public.roles r, public.venues v
			where s.id = _scholar and r.id = _role and v.id = _venue and s.email is not null;
		exception when others then
			raise warning 'add_to_role_and_match: volunteer % was seated but could not be notified: % (%)',
				_v.id, sqlerrm, sqlstate;
		end;
	end if;

	return public.match_assignments(_venue, _name, _role, _scholar);
end;
$$;

alter function public.add_to_role_and_match (uuid, text, uuid, uuid) OWNER to "postgres";

revoke
execute on function public.add_to_role_and_match (uuid, text, uuid, uuid)
from
	public,
	anon;

grant
execute on function public.add_to_role_and_match (uuid, text, uuid, uuid) to authenticated;

--------------------------------------
-- unmatched_name_scholars: the scholars whose name has the same words as an imported name,
-- for whoever staffs the role (see can_staff_role) deciding whom to add to it and match.
--
-- The matching page otherwise offers only the role's accepted volunteers, which is right
-- for matching alone but leaves someone who has a person's agreement with nobody to pick.
-- This is the same rule UnmatchedNameJoined uses, so the person someone was emailed about
-- is the person they find. Emails are included because those who staff a role already see
-- its volunteers' verified addresses, and same-named people can only be told apart by
-- them. Anyone else gets nothing, as does a role from another venue, and an empty key
-- matches nobody.
create or replace function public.unmatched_name_scholars (_venue uuid, _name text, _role uuid) returns table (id uuid, name text, orcid text, email text) language plpgsql security definer stable
set
	search_path to '' as $$
begin
	if not exists (select 1 from public.roles r where r.id = _role and r.venueid = _venue)
		or not public.can_staff_role(_role)
		or public.person_name_key(_name) = '' then
		return;
	end if;
	return query
	select s.id, s.name, s.orcid, s.email
	from public.scholars s
	where public.person_name_key(s.name) = public.person_name_key(_name)
	order by s.name, s.id
	limit 20;
end;
$$;

alter function public.unmatched_name_scholars (uuid, text, uuid) OWNER to "postgres";

revoke
execute on function public.unmatched_name_scholars (uuid, text, uuid)
from
	public,
	anon;

grant
execute on function public.unmatched_name_scholars (uuid, text, uuid) to authenticated;

-- So the lookup above, and every name the notice compares, is an index probe rather than a
-- scan of every scholar.
create index if not exists scholars_name_key_index on public.scholars using btree (public.person_name_key (name));
