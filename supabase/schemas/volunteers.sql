--------------------------------------
-- Schema
create type public.invited as enum('invited', 'accepted', 'declined');

alter type public.invited OWNER to postgres;

create table if not exists public.volunteers (
	-- The unique id of the role
	id uuid default gen_random_uuid() not null,
	-- The id of the scholar who volunteered
	scholarid uuid not null,
	-- The role they volunteered for
	roleid uuid not null,
	-- When this record was last updated
	created_at timestamp with time zone default now() not null,
	-- Relevant expertise provided by the scholar for the role
	expertise text not null,
	-- If the volunteer role is active or inactive, allowing scholars to unvolunteer, then revolunteer.
	-- Allows us to keep the record of volunteering without granting newcomer tokens more than once.
	active boolean default true not null,
	-- Whether this role as been accepted by the scholar
	accepted public.invited default 'accepted'::public.invited not null,
	-- The number of papers the volunteer is committing to review (soft cap; null = unspecified)
	papers integer
);

grant all on table public.volunteers to anon;

grant all on table public.volunteers to authenticated;

grant all on table public.volunteers to service_role;

alter table only public.volunteers
add constraint volunteers_pkey primary key (id);

alter table only public.volunteers
add constraint volunteers_roleid_fkey foreign KEY (roleid) references public.roles (id) on delete cascade;

alter table only public.volunteers
add constraint volunteers_scholarid_fkey foreign KEY (scholarid) references public.scholars (id) on delete cascade;

alter table only public.volunteers
add constraint volunteers_papers_check check (papers is null or papers >= 0);

--------------------------------------
-- Indexes
create index role_volunteer_index on public.volunteers using btree (roleid);

create index scholar_volunteer_index on public.volunteers using btree (scholarid);

--------------------------------------
-- Functions
-- True if the current scholar holds an accepted priority-0 role at the given venue.
-- Used by the tokens UPDATE policy to grant token-management authority.
create or replace function public.isPriorityZero (_venueid uuid) RETURNS boolean LANGUAGE sql SECURITY DEFINER
set
	"search_path" to '' as $$
	select exists (
		select 1
		from public.volunteers v
		join public.roles r on r.id = v.roleid
		where v.scholarid = (select auth.uid())
			and v.accepted = 'accepted'
			and r.venueid = _venueid
			and r.priority = 0
	);
$$;

alter function public.isPriorityZero (_venueid uuid) OWNER to postgres;

grant all on FUNCTION public.isPriorityZero (_venueid uuid) to anon;

grant all on FUNCTION public.isPriorityZero (_venueid uuid) to authenticated;

grant all on FUNCTION public.isPriorityZero (_venueid uuid) to service_role;

--------------------------------------
-- Security
alter table public.volunteers OWNER to postgres;

alter table public.volunteers ENABLE row LEVEL SECURITY;

create policy "anyone can view volunteers" on public.volunteers for
select
	to authenticated,
	anon using (true);

create policy "admins can invite and volunteers if not invite only" on public.volunteers for INSERT to authenticated
with
	check (
		(
			public.isAdmin (
				(
					select
						roles.venueid
					from
						public.roles
					where
						(roles.id=volunteers.roleid)
				)
			)
			or (
				(
					(
						select
							auth.uid () as uid
					)=scholarid
				)
				and (
					not (
						select
							roles.invited
						from
							public.roles
						where
							(roles.id=volunteers.roleid)
					)
				)
			)
		)
	);

create policy "volunteers can update" on public.volunteers
for update
	to authenticated using (
		(
			(
				select
					auth.uid () as uid
			)=scholarid
		)
	);

create policy "admins and volunteers can delete" on public.volunteers for DELETE to authenticated using (
	(
		public.isAdmin (
			(
				select
					roles.venueid
				from
					public.roles
				where
					(roles.id=volunteers.roleid)
			)
		)
		or (
			(
				select
					auth.uid () as uid
			)=scholarid
		)
	)
);

--------------------------------------
-- RPCs (defined in migration 20260608000000_atomic_crud.sql)
-- Internal helper: record the proposed welcome grant for a volunteer. Not
-- granted to any role — only reachable from the SECURITY DEFINER functions
-- below. Creates a proposed venue->scholar transaction sized to welcome_amount;
-- a minter approves it later. No-op for payment-free venues.
create or replace function public._welcome_volunteer (
	_welcomer uuid,
	_scholar uuid,
	_roleid uuid,
	_reason text
) returns void language plpgsql security definer
set
	search_path = public, pg_temp as $function$
declare
	_venue public.venues;
begin
	-- Find the venue that owns the role being volunteered for.
	select v.* into _venue
	from public.venues v
	join public.roles r on r.id = _roleid
	where v.id = r.venueid;
	-- Role or venue gone? Nothing to grant.
	if not found then
		return;
	end if;

	-- Payment-free venues have no tokens, and a zero welcome amount means there
	-- is nothing to grant — either way, do nothing.
	if _venue.payment_free or _venue.welcome_amount <= 0 then
		return;
	end if;

	-- Record the grant as a *proposed* venue->scholar transaction. The tokens
	-- are placeholders (null UUIDs) until a minter approves it via
	-- approve_transaction, which mints and transfers the real tokens.
	insert into public.transactions (
		creator, from_scholar, from_venue, to_scholar, to_venue,
		tokens, currency, purpose, status
	) values (
		_welcomer, null, _venue.id, _scholar, null,
		array_fill('00000000-0000-0000-0000-000000000000'::uuid, array[_venue.welcome_amount]),
		_venue.currency, _reason, 'proposed'
	);
end;
$function$;

revoke execute on function public._welcome_volunteer (uuid, uuid, uuid, text) from public;

-- create_volunteer: insert a volunteer record and, when this is the scholar's
-- first role and compensation is requested, record the proposed welcome grant —
-- atomically. SECURITY DEFINER, re-implementing the volunteers INSERT policy
-- (venue admin, or self for a non-invite-only role).
create or replace function public.create_volunteer (
	_scholarid uuid,
	_roleid uuid,
	_accepted boolean,
	_compensate boolean,
	_papers integer
) returns jsonb language plpgsql security definer
set
	search_path = public, pg_temp as $function$
declare
	_caller uuid;
	_venueid uuid;
	_invited boolean;
	_existing_count integer;
	_volunteer_id uuid;
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

	-- Welcome tokens are granted only once, on the scholar's very first role, so
	-- count their existing volunteer rows before inserting the new one.
	select count(*) into _existing_count from public.volunteers where scholarid = _scholarid;

	-- Create the volunteer record.
	insert into public.volunteers (scholarid, roleid, active, accepted, expertise, papers)
	values (
		_scholarid, _roleid, _accepted,
		case when _accepted then 'accepted'::public.invited else 'invited'::public.invited end,
		'', _papers
	) returning id into _volunteer_id;

	-- First role and compensation requested? Record the welcome grant in the
	-- same transaction, so the volunteer can never exist without it.
	if _existing_count = 0 and _compensate then
		perform public._welcome_volunteer(_caller, _scholarid, _roleid, 'Welcome tokens for volunteering');
	end if;

	-- Return the new volunteer id.
	return jsonb_build_object('volunteer_id', _volunteer_id);
end;
$function$;

revoke execute on function public.create_volunteer (uuid, uuid, boolean, boolean, integer) from public;
grant execute on function public.create_volunteer (uuid, uuid, boolean, boolean, integer) to authenticated;

-- accept_role_invite: respond to a role invitation and, when accepting a first
-- role, record the proposed welcome grant — atomically. SECURITY DEFINER,
-- re-implementing the volunteers UPDATE policy (only the volunteering scholar).
create or replace function public.accept_role_invite (
	_volunteer_id uuid,
	_response public.invited
) returns jsonb language plpgsql security definer
set
	search_path = public, pg_temp as $function$
declare
	_caller uuid;
	_v public.volunteers;
	_total integer;
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

	-- Count the scholar's volunteer rows to detect a first-role acceptance.
	select count(*) into _total from public.volunteers where scholarid = _v.scholarid;

	-- Apply the response and (re)activate the record.
	update public.volunteers set active = true, accepted = _response where id = _volunteer_id;

	-- Accepting a first invitation earns the welcome grant, recorded atomically.
	if _total = 1 and _v.accepted = 'invited' and _response = 'accepted' then
		perform public._welcome_volunteer(_v.scholarid, _v.scholarid, _v.roleid, 'Welcome tokens for accepting role invite');
	end if;

	-- Return the volunteer id that was updated.
	return jsonb_build_object('volunteer_id', _volunteer_id);
end;
$function$;

revoke execute on function public.accept_role_invite (uuid, public.invited) from public;
grant execute on function public.accept_role_invite (uuid, public.invited) to authenticated;

alter publication supabase_realtime
add table volunteers;
