-- assignment_loads: true per-role counts of active assignments, for the editors choosing
-- reviewers. See supabase/schemas/assignments.sql for why it is SECURITY DEFINER.
--
-- The revoke travels in this migration: Supabase's default privileges grant anon
-- EXECUTE on a function every time it is re-created.

create or replace function public.assignment_loads (_venue uuid, _scholars uuid[]) returns table (scholar uuid, role uuid, count integer) language sql security definer stable
set
	"search_path" to '' as $$
	with approving as (
		select held.id
		from public.roles held
		where held.venueid = _venue
		  and (held.priority = 0 or exists (select 1 from public.roles r where r.approver = held.id))
	),
	allowed as (
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
		) as ok
	)
	select a.scholar, a.role, count(*)::integer
	from public.assignments a, allowed
	where allowed.ok
	  and a.venue = _venue
	  and a.scholar = any (_scholars)
	  and a.approved
	  and not a.completed
	group by a.scholar, a.role
	union all
	select a.scholar, null, count(*)::integer
	from public.assignments a
	join public.roles r on r.id = a.role, allowed
	where allowed.ok
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
