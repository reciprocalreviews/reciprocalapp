-- Let whoever staffs a role add someone who was invited and never answered, from the
-- invite form's "They already agreed" path, rather than only from matching an imported
-- name. The seating step add_to_role_and_match did inline moves into _enroll_volunteer so
-- both paths share it; add_to_role replaces the client's loop over create_volunteer.

--------------------------------------
-- _enroll_volunteer: seat an existing volunteer record on the scholar's behalf. An
-- unanswered invitation becomes an acceptance and a paused record resumes.
--
-- A step of add_to_role and add_to_role_and_match, which authorize the caller, confirm the
-- scholar agreed, and decide which records qualify. So it performs no authorization of its
-- own and is owner-only.
--
-- Accepting a first invitation at the venue earns its welcome grant, as it would have through
-- accept_role_invite, and the scholar is emailed RoleEnrolled, as anyone create_volunteer
-- seats directly is. The email is best effort: no failure to compose it may undo the seat.
create or replace function public._enroll_volunteer (_caller uuid, _volunteer uuid) returns void language plpgsql security definer
set
	search_path to '' as $$
declare
	_v public.volunteers;
	_venue uuid;
	_total integer;
begin
	select * into _v from public.volunteers where id = _volunteer;
	if not found then
		raise exception 'Volunteer record not found';
	end if;
	select r.venueid into _venue from public.roles r where r.id = _v.roleid;

	update public.volunteers set accepted = 'accepted', active = true where id = _v.id;

	if _v.accepted = 'invited' then
		select count(*) into _total
		from public.volunteers v
		join public.roles r on r.id = v.roleid
		where v.scholarid = _v.scholarid and r.venueid = _venue;
		if _total = 1 then
			perform public._welcome_volunteer(_caller, _v.scholarid, _v.roleid, 'Welcome tokens for joining a role');
		end if;
	end if;

	begin
		insert into public.emails (event, scholar, sender, venue, email, subject, message, args)
		select
			'RoleEnrolled', s.id, _caller, _venue, s.email, null, null,
			to_jsonb(array[r.name, v.title, coalesce(v.slug, v.id::text), s.id::text])
		from public.scholars s, public.roles r, public.venues v
		where s.id = _v.scholarid and r.id = _v.roleid and v.id = _venue and s.email is not null;
	exception when others then
		raise warning '_enroll_volunteer: volunteer % was seated but could not be notified: % (%)',
			_v.id, sqlerrm, sqlstate;
	end;
end;
$$;

alter function public._enroll_volunteer (uuid, uuid) OWNER to "postgres";

revoke
execute on function public._enroll_volunteer (uuid, uuid)
from
	public,
	anon,
	authenticated;

--------------------------------------
-- add_to_role: whoever staffs the role (see can_staff_role), having confirmed each scholar
-- agreed to it, seats them in it with no invitation to accept. This is the invite form's
-- "They already agreed" path.
--
-- Someone with no record here is seated by create_volunteer. Someone invited who never
-- answered is seated on their behalf (_enroll_volunteer). They agreed some other way, and
-- until they clicked accept they could not be assigned to anything.
--
-- A declined invitation is refused (RR027), as in add_to_role_and_match: the person said no
-- on the platform. A record that is already accepted is refused too (RR004), paused ones
-- included. Pausing was the volunteer's own choice, and this form brings people in rather
-- than overriding them.
--
-- The whole list is one transaction, so a refusal partway through seats nobody.
create or replace function public.add_to_role (_role uuid, _scholars uuid[]) returns uuid[] language plpgsql security definer
set
	search_path to '' as $$
declare
	_caller uuid := (select auth.uid());
	_scholar uuid;
	_v public.volunteers;
	_ids uuid[] := '{}';
begin
	if _caller is null then
		raise exception 'Authentication required';
	end if;

	if not public.can_staff_role(_role) then
		raise exception 'Only those who approve this role may add someone to it';
	end if;

	if coalesce(cardinality(_scholars), 0) = 0 then
		raise exception 'Nobody to add to this role';
	end if;

	for _scholar in select distinct s from unnest(_scholars) as s loop
		select * into _v from public.volunteers where scholarid = _scholar and roleid = _role;
		if not found then
			-- Seats, grants any welcome tokens, and emails RoleEnrolled.
			_ids := _ids || (public.create_volunteer(_scholar, _role, true, true, null) ->> 'volunteer_id')::uuid;
		elsif _v.accepted = 'invited' then
			perform public._enroll_volunteer(_caller, _v.id);
			_ids := _ids || _v.id;
		elsif _v.accepted = 'declined' then
			raise exception 'They declined this role, so they cannot be added to it'
				using errcode = 'RR027';
		else
			raise exception 'Already volunteered for this role' using errcode = 'RR004';
		end if;
	end loop;

	return _ids;
end;
$$;

alter function public.add_to_role (uuid, uuid[]) OWNER to "postgres";

revoke
execute on function public.add_to_role (uuid, uuid[])
from
	public,
	anon;

grant
execute on function public.add_to_role (uuid, uuid[]) to authenticated;

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
		-- Accepts or resumes, grants any first-role welcome tokens, and emails RoleEnrolled.
		perform public._enroll_volunteer(_caller, _v.id);
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
