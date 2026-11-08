-- Decline reasons (#218). An approver declining a bid or claim had to write the
-- explanation from scratch, and words written in a hurry can read more harshly than
-- intended. Each venue now keeps an ordered list of neutral reasons; an approver picks one
-- or writes their own. A venue that deletes them all requires written
-- reasons, as before. The chosen reason's text is copied onto the assignment (so later
-- edits never rewrite what a bidder was told) and its id kept (so declines are countable).
--
-- Every venue, new and existing, starts with five defaults.
--
-- decline_bid's signature changes, so the old one is dropped rather than overloaded. The
-- revokes travel in this migration: Supabase's default privileges grant anon EXECUTE on a
-- function every time it is created.

--------------------------------------
-- Schema
--
-- The reasons a venue offers its approvers when they decline a bid or claim. A decline is
-- addressed to a person, and a free-text explanation written in a hurry can read more
-- harshly than intended; a venue's own neutral wording keeps the answer consistent and
-- makes declines countable. A venue with none requires approvers to write each one.
create table if not exists public.decline_reasons (
	-- The unique id of the reason
	id uuid default gen_random_uuid() not null,
	-- The venue this reason belongs to
	venueid uuid not null,
	-- The words the declined scholar reads
	text text not null,
	-- The presentation order; lower rank is shown first
	rank integer not null,
	-- When the reason was created
	created_at timestamp with time zone default now() not null
);

alter table only public.decline_reasons
add constraint decline_reasons_pkey primary key (id);

alter table only public.decline_reasons
add constraint decline_reasons_venueid_fkey foreign KEY (venueid) references public.venues (id) on delete cascade;

alter table only public.decline_reasons
add constraint decline_reasons_venue_rank_unique unique (venueid, rank);

alter table only public.decline_reasons
add constraint decline_reasons_venue_text_unique unique (venueid, text);

-- The same bound as assignments.decline_reason, which a chosen reason is copied into.
alter table only public.decline_reasons
add constraint decline_reasons_text_check check (char_length(btrim(text)) between 1 and 1000);

alter table only public.decline_reasons
add constraint decline_reasons_rank_check check (rank>=0);

create index decline_reasons_venue_index on public.decline_reasons using btree (venueid);

--------------------------------------
-- Defaults
--
-- Every new venue starts with these, so approvers have neutral wording from the first
-- decline; admins edit them or delete them all to require written reasons.
create or replace function public._seed_decline_reasons () returns trigger language plpgsql security definer
set
	search_path to '' as $$
begin
	insert into public.decline_reasons (venueid, text, rank)
	values
		(new.id, 'We needed someone with different expertise.', 0),
		(new.id, 'We selected a different scholar.', 1),
		(new.id, 'We already have enough reviewers for this submission.', 2),
		(new.id, 'Other qualified scholars were in more need of tokens.', 3),
		(new.id, 'We wanted to avoid a possible conflict of interest.', 4);
	return new;
end;
$$;

alter function public._seed_decline_reasons () OWNER to "postgres";

revoke
execute on function public._seed_decline_reasons ()
from
	public,
	anon,
	authenticated;

create or replace trigger seed_decline_reasons
after insert on public.venues for each row
execute function public._seed_decline_reasons ();

--------------------------------------
-- Security
alter table public.decline_reasons OWNER to postgres;

alter table public.decline_reasons ENABLE row LEVEL SECURITY;

grant all on table public.decline_reasons to anon;

grant all on table public.decline_reasons to authenticated;

grant all on table public.decline_reasons to service_role;

create policy "authenticated scholars can view decline reasons" on public.decline_reasons for
select
	to authenticated using (true);

create policy "only admins can create decline reasons" on public.decline_reasons for INSERT to authenticated
with
	check (public.isAdmin (venueid));

create policy "only admins can update decline reasons" on public.decline_reasons
for update
	to authenticated using (public.isAdmin (venueid));

create policy "only admins can delete decline reasons" on public.decline_reasons for DELETE to authenticated using (public.isAdmin (venueid));

alter publication supabase_realtime
add table decline_reasons;

-- Existing venues get the same defaults new ones do.
insert into public.decline_reasons (venueid, text, rank)
select v.id, d.text, d.rank
from public.venues v
cross join (
	values
		('We needed someone with different expertise.', 0),
		('We selected a different scholar.', 1),
		('We already have enough reviewers for this submission.', 2),
		('Other qualified scholars were in more need of tokens.', 3),
		('We wanted to avoid a possible conflict of interest.', 4)
) as d (text, rank);

create or replace trigger decline_reasons_audit after insert or update or delete on public.decline_reasons
for each row execute function public.log_audit_event();

--------------------------------------
-- Assignments

alter table public.assignments
add column decline_reason_id uuid default null;

alter table only public.assignments
add constraint "assignments_decline_reason_id_fkey" foreign KEY (decline_reason_id) references public.decline_reasons (id) on delete set null;

alter table only public.assignments
add constraint assignments_decline_reason_id_check check (
	decline_reason_id is null
	or declined_at is not null
);

create or replace function public.enforce_assignment_updates () RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER
set
	"search_path" to '' as $$
begin
	if new.approved and not old.approved then
		new.declined_at := null;
		new.declined_by := null;
		new.decline_reason := null;
		new.decline_reason_id := null;
	end if;

	if current_user <> 'authenticated' then
		return new;
	end if;

	if (new.scholar, new.role, new.submission, new.venue, new.bid)
		is distinct from (old.scholar, old.role, old.submission, old.venue, old.bid) then
		raise exception 'An assignment''s scholar, role, submission and bid cannot be changed'
			using errcode = 'RR018';
	end if;

	if (new.approved, new.completed, new.declined_at, new.declined_by, new.decline_reason,
			new.decline_reason_id)
		is distinct from (old.approved, old.completed, old.declined_at, old.declined_by, old.decline_reason,
			old.decline_reason_id)
		and not public.can_approve_assignment(old.submission, old.role) then
		raise exception 'Only an approver of this role may approve, complete or decline this assignment'
			using errcode = 'RR018';
	end if;

	return new;
end;
$$;

alter function public.enforce_assignment_updates () OWNER to "postgres";

revoke
execute on function public.enforce_assignment_updates ()
from
	public,
	anon;

drop function public.decline_bid (uuid, text);

create or replace function public.decline_bid (
	_assignment uuid,
	_reason text,
	_reason_id uuid default null
) returns jsonb language plpgsql security definer
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
	if _reason_id is not null then
		if char_length(_trimmed) > 0 then
			raise exception 'A decline gives the venue''s reason or the approver''s own, not both';
		end if;
		select r.text into _trimmed from public.decline_reasons r
		where r.id = _reason_id and r.venueid = _a.venue;
		if not found then
			raise exception 'That decline reason does not belong to this venue';
		end if;
	else
		if char_length(_trimmed) = 0 then
			raise exception 'A declined bid needs an explanation for the bidder';
		end if;
		if char_length(_trimmed) > 1000 then
			raise exception 'An explanation must be at most 1000 characters';
		end if;
	end if;

	update public.assignments
	set declined_at = now(), declined_by = _caller, decline_reason = _trimmed,
		decline_reason_id = _reason_id
	where id = _assignment;

	return jsonb_build_object(
		'venue', _a.venue,
		'submission', _a.submission,
		'scholar', _a.scholar,
		'role', _a.role,
		'reason', _trimmed
	);
end;
$$;

alter function public.decline_bid (uuid, text, uuid) OWNER to "postgres";

revoke
execute on function public.decline_bid (uuid, text, uuid)
from
	public,
	anon;

grant
execute on function public.decline_bid (uuid, text, uuid) to authenticated;
