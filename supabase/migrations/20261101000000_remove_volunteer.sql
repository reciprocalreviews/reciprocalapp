-- Venue leaders can take a volunteer out of a role. Admins and holders of the venue's
-- top-priority role may mark another scholar's accepted volunteer record inactive, and the
-- scholar is emailed (RoleRemoved). Deactivation, never deletion, for the welcome grant's
-- sake; the volunteer may resume. The revokes travel in this migration: Supabase's default
-- privileges grant anon EXECUTE on a function every time it is created.

-- remove_volunteer: a venue's leaders mark another scholar's volunteer record inactive.
--
-- Leaving a role was always possible (a volunteer toggles their own `active`), but
-- nobody could take someone else out of one: the UPDATE policy admits only the
-- volunteering scholar, and DELETE is refused outright because the row is what keeps
-- the welcome grant one-time. So this deactivates rather than deletes, exactly as
-- stopping does, and the volunteer may resume afterwards just as they could after
-- stopping themselves. It is a statement that the venue is not counting on them, not
-- a ban.
--
-- Authorized for venue admins and for holders of the venue's top-priority role, who
-- oversee every other role. SECURITY DEFINER because the UPDATE policy would refuse
-- them. Callers may not remove themselves (that is Stop, which tells the venue rather
-- than the volunteer), and only accepted records can be removed: an invitation is
-- answered by the person invited, not withdrawn from under them.
--
-- The volunteer is told. Consequential: a commitment changed without their asking,
-- the mirror of RoleEnrolled. Best effort, like create_volunteer's notice -- the
-- deactivation is what must not be lost.
create or replace function public.remove_volunteer (_volunteer_id uuid) returns jsonb language plpgsql security definer
set
	search_path=public,
	pg_temp as $function$
declare
	_caller uuid;
	_v public.volunteers;
	_venueid uuid;
	_notified boolean := false;
begin
	-- Identify and require an authenticated caller.
	_caller := (select auth.uid());
	if _caller is null then
		raise exception 'Authentication required';
	end if;

	select * into _v from public.volunteers where id = _volunteer_id;
	if not found then
		raise exception 'Volunteer record not found';
	end if;
	select venueid into _venueid from public.roles where id = _v.roleid;

	if not (public.isAdmin(_venueid) or public.isPriorityZero(_venueid)) then
		raise exception 'Only venue admins and the top role may remove volunteers';
	end if;
	if _caller = _v.scholarid then
		raise exception 'Stop volunteering instead of removing yourself';
	end if;
	if _v.accepted <> 'accepted' then
		raise exception 'Only accepted volunteers can be removed';
	end if;

	-- Already inactive: nothing changes, and nobody needs telling twice.
	if not _v.active then
		return jsonb_build_object('volunteer_id', _volunteer_id, 'notified', false);
	end if;

	update public.volunteers set active = false where id = _volunteer_id;

	begin
		insert into public.emails (event, scholar, sender, venue, email, subject, message, args)
		select
			'RoleRemoved', s.id, _caller, _venueid, s.email, null, null,
			to_jsonb(array[
				r.name,
				v.title,
				coalesce(v.slug, v.id::text),
				s.id::text
			])
		from public.scholars s, public.roles r, public.venues v
		where s.id = _v.scholarid
			and r.id = _v.roleid
			and v.id = _venueid
			and s.email is not null;
		_notified := found;
	exception when others then
		raise warning 'remove_volunteer: volunteer % was removed but could not be notified: % (%)',
			_volunteer_id, sqlerrm, sqlstate;
	end;

	return jsonb_build_object('volunteer_id', _volunteer_id, 'notified', _notified);
end;
$function$;

revoke
execute on function public.remove_volunteer (uuid)
from
	public,
	anon;

grant
execute on function public.remove_volunteer (uuid) to authenticated;
