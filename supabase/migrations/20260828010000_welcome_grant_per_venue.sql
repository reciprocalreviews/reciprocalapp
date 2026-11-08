-- Grant a venue's welcome tokens once per scholar PER VENUE.
--
-- venues.welcome_amount is standing policy of one venue, denominated in that
-- venue's own currency. But the first-time check that gated the grant counted
-- the scholar's volunteer rows platform-wide:
--
--   select count(*) into _existing_count
--   from public.volunteers where scholarid = _scholarid;
--
-- so a scholar who had ever volunteered anywhere received nothing at every
-- venue they joined afterward — even though they hold none of that venue's
-- currency and are a newcomer to its community. The failure was silent: the
-- RPC returned welcome_granted 0 and the confirmation simply omitted the
-- token sentence. accept_role_invite had the same defect, as `_total = 1`.
--
-- Both counts now join roles and filter on the role's venue. _welcome_volunteer
-- is unchanged: it already resolves the venue from _roleid and was correct.
-- Neither signature nor return type changes, so create or replace suffices.
--
-- Forward-only. Scholars already denied a grant at a venue they joined are not
-- backfilled; doing so would retroactively expand those venues' token supply.

-- create_volunteer: insert a volunteer record and, when this is the scholar's
-- first role at the role's venue and compensation is requested, settle the
-- welcome grant — atomically. SECURITY DEFINER, re-implementing the volunteers
-- INSERT policy (venue admin, or self for a non-invite-only role).
create or replace function public.create_volunteer (
	_scholarid uuid,
	_roleid uuid,
	_accepted boolean,
	_compensate boolean,
	_papers integer
) returns jsonb language plpgsql security definer
set
	search_path=public,
	pg_temp as $function$
declare
	_caller uuid;
	_venueid uuid;
	_invited boolean;
	_existing_count integer;
	_volunteer_id uuid;
	_granted integer := 0;
begin
	-- Identify and require an authenticated caller.
	_caller := (select auth.uid());
	if _caller is null then
		raise exception 'Authentication required';
	end if;

	-- Look up the role's venue and whether it is invite-only.
	select venueid, invited into _venueid, _invited from public.roles where id = _roleid;
	if _venueid is null then
		raise exception 'Role not found';
	end if;

	-- A venue admin may add anyone; otherwise a scholar may only add themselves,
	-- and only to a role that is not invite-only.
	if not (public.isAdmin(_venueid) or (_caller = _scholarid and not _invited)) then
		raise exception 'You are not authorized to volunteer for this role';
	end if;

	-- No duplicate volunteering for the same role. RR004 surfaces the specific
	-- "already volunteered" message.
	if exists (select 1 from public.volunteers where scholarid = _scholarid and roleid = _roleid) then
		raise exception 'Already volunteered for this role' using errcode = 'RR004';
	end if;

	-- Welcome tokens are standing policy of one venue, so they are granted once
	-- per scholar per venue: someone who volunteered elsewhere is still a
	-- newcomer here, and this venue's currency is not one they already hold.
	-- Count only their existing volunteer rows at this venue, before inserting
	-- the new one.
	select count(*) into _existing_count
	from public.volunteers v
	join public.roles r on r.id = v.roleid
	where v.scholarid = _scholarid and r.venueid = _venueid;

	-- Create the volunteer record.
	insert into public.volunteers (scholarid, roleid, active, accepted, expertise, papers)
	values (
		_scholarid, _roleid, _accepted,
		case when _accepted then 'accepted'::public.invited else 'invited'::public.invited end,
		'', _papers
	) returning id into _volunteer_id;

	-- First role at this venue and compensation requested? Settle the welcome
	-- grant in the same transaction, so the volunteer can never exist without it.
	if _existing_count = 0 and _compensate then
		_granted := public._welcome_volunteer(_caller, _scholarid, _roleid, 'Welcome tokens for volunteering');
	end if;

	-- Return the new volunteer id and what the grant actually came to.
	return jsonb_build_object('volunteer_id', _volunteer_id, 'welcome_granted', _granted);
end;
$function$;

revoke
execute on function public.create_volunteer (uuid, uuid, boolean, boolean, integer)
from
	public;

grant
execute on function public.create_volunteer (uuid, uuid, boolean, boolean, integer) to authenticated;

-- accept_role_invite: respond to a role invitation and, when accepting a first
-- role at the role's venue, settle the welcome grant — atomically. SECURITY
-- DEFINER, re-implementing the volunteers UPDATE policy (only the volunteering
-- scholar).
create or replace function public.accept_role_invite (_volunteer_id uuid, _response public.invited) returns jsonb language plpgsql security definer
set
	search_path=public,
	pg_temp as $function$
declare
	_caller uuid;
	_v public.volunteers;
	_venueid uuid;
	_total integer;
	_granted integer := 0;
begin
	-- Identify and require an authenticated caller.
	_caller := (select auth.uid());
	if _caller is null then
		raise exception 'Authentication required';
	end if;

	-- Load the invitation; only the invited scholar may respond to it.
	select * into _v from public.volunteers where id = _volunteer_id;
	if not found then
		raise exception 'Volunteer record not found';
	end if;
	if _caller <> _v.scholarid then
		raise exception 'You can only respond to your own invitations';
	end if;

	-- Count the scholar's volunteer rows at this role's venue to detect a
	-- first-role acceptance here; the grant is once per scholar per venue. The
	-- invitation row already exists, so a count of 1 means it is their only one.
	select venueid into _venueid from public.roles where id = _v.roleid;
	select count(*) into _total
	from public.volunteers v
	join public.roles r on r.id = v.roleid
	where v.scholarid = _v.scholarid and r.venueid = _venueid;

	-- Apply the response and (re)activate the record.
	update public.volunteers set active = true, accepted = _response where id = _volunteer_id;

	-- Accepting a first invitation at this venue earns its welcome grant,
	-- recorded atomically.
	if _total = 1 and _v.accepted = 'invited' and _response = 'accepted' then
		_granted := public._welcome_volunteer(_v.scholarid, _v.scholarid, _v.roleid, 'Welcome tokens for accepting role invite');
	end if;

	-- Return the volunteer id that was updated and what the grant came to.
	return jsonb_build_object('volunteer_id', _volunteer_id, 'welcome_granted', _granted);
end;
$function$;

revoke
execute on function public.accept_role_invite (uuid, public.invited)
from
	public;

grant
execute on function public.accept_role_invite (uuid, public.invited) to authenticated;

