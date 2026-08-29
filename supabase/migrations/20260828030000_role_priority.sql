-- Roles are ordered by `priority`, and zero is not merely presentation: it is what
-- public.isPriorityZero(), public.can_approve_assignment(), the submissions author-list
-- lock and public.mark_submission_done() check when deciding who acts as an editor.
--
-- The column defaults to 0 and the client inserted roles without one, so every role a
-- venue admin created landed at priority 0 — silently granting its accepted volunteers
-- editor authority, and leaving several role cards each claiming to be the venue's
-- highest priority role. Nothing corrected it until an admin happened to press the
-- reorder arrows, which renumber the whole venue as a side effect.
--
-- This migration does two things: gives new roles a priority of their own, and renumbers
-- the venues that already have ties.
--------------------------------------
-- 1. Create roles at the bottom of the order.
--
-- security invoker, so the existing "only admins can create venue roles" policy remains
-- the only authorization check. The advisory lock is what makes max + 1 safe: two admins
-- adding a role to the same venue at once would otherwise both read the same maximum.
-- A venue's first role still lands at 0, so proposal approval's default Editor is
-- unaffected.
create or replace function public.create_role (
	_venue uuid,
	_name text,
	_description text default ''
) returns public.roles language plpgsql security invoker
set
	"search_path" to '' as $$
declare
	_role public.roles;
begin
	perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(_venue::text, 0));

	insert into public.roles (venueid, invited, name, description, priority)
	values (
		_venue, true, _name, _description,
		coalesce((select max(priority) + 1 from public.roles where venueid = _venue), 0)
	)
	returning * into _role;

	return _role;
end;
$$;

alter function public.create_role (uuid, text, text) OWNER to postgres;

grant all on FUNCTION public.create_role (uuid, text, text) to authenticated;

--------------------------------------
-- 2. Renumber every venue densely, 0..n-1.
--
-- Ties have to be broken by something, and which role keeps 0 decides who keeps editor
-- authority, so the order is chosen to land on the role a venue would call its editors:
--   1. existing priority, so any venue that was already ordered keeps that order;
--   2. how many of its accepted volunteers are venue admins — approving a proposal
--      enrols every editor as an accepted volunteer in the default Editor role, so this
--      picks that role out of a pile of ties;
--   3. how many other roles name it as their approver, since an editor role is typically
--      the top of the approval chain;
--   4. id, so the result is deterministic rather than dependent on scan order.
--
-- public.roles is audited, so this is recorded in public.audit_log with a null actor.
with ranked as (
	select
		r.id,
		row_number() over (
			partition by r.venueid
			order by
				r.priority,
				(
					select count(*)
					from public.volunteers v
					join public.venues ven on ven.id = r.venueid
					where v.roleid = r.id
						and v.accepted = 'accepted'
						and v.scholarid = any (ven.admins)
				) desc,
				(select count(*) from public.roles o where o.approver = r.id) desc,
				r.id
		) - 1 as priority
	from public.roles r
)
update public.roles r
set priority = ranked.priority
from ranked
where ranked.id = r.id
	and r.priority is distinct from ranked.priority;
