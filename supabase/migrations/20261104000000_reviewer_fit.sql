-- Reviewer fit: rank volunteers by evidence of fit for those who scout the roster.
--
--   * venues.relevant_venues: the journals and proceedings a venue's community publishes in.
--   * orcid_profiles.work_journals: every journal title across a scholar's full ORCID
--     record, with counts, so "has ever published in a relevant venue" is answerable.
--   * can_scout_volunteers: the gate assignment_loads applied inline, lifted out so
--     completed_counts shares it rather than restating it.
--   * completed_counts: reviews finished at the venue, per scholar.

alter table public.venues
add column if not exists relevant_venues text[] default '{}'::text[] not null;

alter table public.venues
add constraint venues_relevant_venues_check check (
	cardinality(relevant_venues)<=20
	and length(array_to_string(relevant_venues, ''))<=2000
);

alter table public.orcid_profiles
add column if not exists work_journals jsonb not null default '[]';

alter table only public.orcid_profiles
add constraint orcid_profiles_work_journals_shape check (
	jsonb_typeof(work_journals)='array'
	and jsonb_array_length(work_journals)<=100
);

-- The column grant names its columns, so a new column is unreadable until named.
grant
select
	(work_journals) on table public.orcid_profiles to anon,
	authenticated;

-- Existing rows have no work_journals until their works are read again, which would
-- otherwise wait up to ninety days. Clearing the works clock makes the next claim re-read
-- them; claims stay batched and cooled down, so this spreads out rather than stampedes.
update public.orcid_profiles
set
	works_fetched_at = null;

-- Whether the caller helps run the venue's reviewing, and so may see the counts the
-- volunteers roster scouts with (assignment_loads, completed_counts): an admin, or a
-- scholar who volunteers for (accepted) or holds an active seat in the priority-0 role or
-- a role that approves another. The volunteer half mirrors src/lib/data/isVenueApprover.ts,
-- so an editor scouting the roster before any paper is theirs sees the same numbers; the
-- seat half covers someone approving without a volunteer record. Anyone else: false.
create or replace function public.can_scout_volunteers (_venue uuid) returns boolean language sql security definer stable
set
	"search_path" to '' as $$
	with approving as (
		select held.id
		from public.roles held
		where held.venueid = _venue
		  and (held.priority = 0 or exists (select 1 from public.roles r where r.approver = held.id))
	)
	select public.isAdmin(_venue) or exists (
		select 1
		from public.volunteers v
		where v.scholarid = (select auth.uid())
		  and v.accepted = 'accepted'
		  and v.roleid in (select id from approving)
	) or exists (
		select 1
		from public.assignments a
		where a.scholar = (select auth.uid())
		  and a.approved
		  and not a.completed
		  and a.role in (select id from approving)
	);
$$;

alter function public.can_scout_volunteers (uuid) OWNER to "postgres";

revoke
execute on function public.can_scout_volunteers (uuid)
from
	public,
	anon;

grant
execute on function public.can_scout_volunteers (uuid) to authenticated;

-- Only someone who helps run the venue's reviewing gets rows: see can_scout_volunteers.
create or replace function public.assignment_loads (_venue uuid, _scholars uuid[]) returns table (scholar uuid, role uuid, count integer) language sql security definer stable
set
	"search_path" to '' as $$
	select a.scholar, a.role, count(*)::integer
	from public.assignments a
	where public.can_scout_volunteers(_venue)
	  and a.venue = _venue
	  and a.scholar = any (_scholars)
	  and a.approved
	  and not a.completed
	group by a.scholar, a.role
	union all
	select a.scholar, null, count(*)::integer
	from public.assignments a
	join public.roles r on r.id = a.role
	where public.can_scout_volunteers(_venue)
	  and a.venue <> _venue
	  and a.scholar = any (_scholars)
	  and a.approved
	  and not a.completed
	  and r.priority > 0
	group by a.scholar
	order by 1, 2 nulls last;
$$;

alter function public.assignment_loads (uuid, uuid[]) OWNER to "postgres";

revoke
execute on function public.assignment_loads (uuid, uuid[])
from
	public,
	anon;

grant
execute on function public.assignment_loads (uuid, uuid[]) to authenticated;

-- How many reviews each scholar has finished at the venue, for the volunteers roster's
-- track record: someone who has completed work here is the strongest evidence of fit a
-- venue has. Counts only, never which submissions, and only for the same people
-- assignment_loads answers, since the ordering it drives is shown to no one else.
-- Rows: (scholar, count) for approved, completed assignments in _venue in any role. Zero
-- counts are omitted. Ordered so the client can page past PostgREST's max_rows.
create or replace function public.completed_counts (_venue uuid, _scholars uuid[]) returns table (scholar uuid, count integer) language sql security definer stable
set
	"search_path" to '' as $$
	select a.scholar, count(*)::integer
	from public.assignments a
	where public.can_scout_volunteers(_venue)
	  and a.venue = _venue
	  and a.scholar = any (_scholars)
	  and a.approved
	  and a.completed
	group by a.scholar
	order by 1;
$$;

alter function public.completed_counts (uuid, uuid[]) OWNER to "postgres";

revoke
execute on function public.completed_counts (uuid, uuid[])
from
	public,
	anon;

grant
execute on function public.completed_counts (uuid, uuid[]) to authenticated;
