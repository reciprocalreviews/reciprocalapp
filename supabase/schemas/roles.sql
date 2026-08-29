--------------------------------------
-- Schema
create table if not exists public.roles (
	-- The unique id of the role
	id uuid default gen_random_uuid() not null,
	-- The ID of the venue
	venueid uuid not null,
	-- The name of the role
	name text default ''::text not null,
	-- The rich text description of the role
	description text default ''::text not null,
	-- Whether the role is invite only. If true, only role approvers can invite scholars to the role.
	invited boolean not null,
	-- Whether the role is biddable. If true, scholars can bid on submissions with the role.
	biddable boolean default false not null,
	-- The role that can approve assignments to this role
	approver uuid,
	-- The presentation order of the role, lower is more important
	priority integer default 0 not null,
	-- Whether authors are visible to scholars assigned to a submission
	anonymous_authors boolean default true not null,
	-- The number of assignments after which bidding should be turned off. Null for no limit.
	desired_assignments integer not null default 1
);

alter table only public.roles
add constraint "roles_pkey" primary key (id);

alter table only public.roles
add constraint "roles_approver_fkey" foreign KEY ("approver") references public.roles (id) on delete set null;

alter table only public.roles
add constraint "roles_venueid_fkey" foreign KEY ("venueid") references public.venues (id) on delete cascade;

create index roles_venue_index on public.roles using btree (venueid);

--------------------------------------
-- Functions
-- Create a role at the bottom of a venue's priority order.
--
-- Priority is not merely presentation. Zero is what public.isPriorityZero(),
-- public.can_approve_assignment(), the submissions author-list lock and
-- public.mark_submission_done() all check when deciding who acts as an editor. Because
-- the column defaults to 0, a plain insert made every role an admin created an editor
-- role, and left several of them claiming to be the venue's first. Taking max + 1 here
-- keeps priorities unique within a venue and keeps that authority where an admin put it.
-- A venue's first role still lands at 0, so proposal approval's default Editor is
-- unaffected.
--
-- security invoker, so the "only admins can create venue roles" policy below remains the
-- only authorization check. The advisory lock is what makes max + 1 safe: two admins
-- adding a role to the same venue at once would otherwise both read the same maximum.
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
-- Security
alter table public.roles OWNER to "postgres";

alter table public.roles ENABLE row LEVEL SECURITY;

create policy "anyone can view roles" on public.roles for
select
	to authenticated,
	anon using (true);

create policy "only admins can create venue roles" on public.roles for INSERT to authenticated
with
	check (public.isAdmin (venueid));

create policy "only admins can update roles" on public.roles
for update
	to authenticated using (public.isAdmin (venueid));

create policy "only admins can delete roles" on public.roles for DELETE to authenticated using (public.isAdmin (venueid));

grant all on table public.roles to "anon";

grant all on table public.roles to "authenticated";

grant all on table public.roles to "service_role";

alter publication supabase_realtime
add table roles;
