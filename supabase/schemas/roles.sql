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
	-- The token compensation for a commitment, in the venue's currency
	amount integer not null,
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
-- Security
alter table public.roles OWNER to "postgres";

alter table public.roles ENABLE row LEVEL SECURITY;

create policy "anyone can view roles" on public.roles for
select
	to "authenticated",
	"anon" using (true);

create policy "only admins can create venue roles" on public.roles for INSERT to "authenticated",
"anon"
with
	check (public.isAdmin (venueid));

create policy "only admins can update roles" on public.roles
for update
	to "authenticated",
	"anon" using (public.isAdmin (venueid));

create policy "only admins can delete roles" on public.roles for DELETE to "authenticated",
"anon" using (public.isAdmin (venueid));

grant all on table public.roles to "anon";

grant all on table public.roles to "authenticated";

grant all on table public.roles to "service_role";
