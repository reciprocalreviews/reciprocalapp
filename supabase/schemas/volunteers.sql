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
	created timestamp with time zone default now() not null,
	-- Relevant expertise provided by the scholar for the role
	expertise text not null,
	-- If the volunteer role is active or inactive, allowing scholars to unvolunteer, then revolunteer.
	-- Allows us to keep the record of volunteering without granting newcomer tokens more than once.
	active boolean default true not null,
	-- Whether this role as been accepted by the scholar
	accepted public.invited default 'accepted'::public.invited not null
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

--------------------------------------
-- Indexes
create index role_volunteer_index on public.volunteers using btree (roleid);

create index scholar_volunteer_index on public.volunteers using btree (scholarid);

--------------------------------------
-- Security
alter table public.volunteers OWNER to postgres;

alter table public.volunteers ENABLE row LEVEL SECURITY;

create policy "anyone can view volunteers" on public.volunteers for
select
	to authenticated,
	anon using (true);

create policy "editors can invite and volunteers if not invite only" on public.volunteers for INSERT to authenticated,
anon
with
	check (
		(
			public.isEditor (
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
	to authenticated,
	anon using (
		(
			(
				select
					auth.uid () as uid
			)=scholarid
		)
	);

create policy "editors and volunteers can delete" on public.volunteers for DELETE to authenticated,
anon using (
	(
		public.isEditor (
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
