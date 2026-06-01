--------------------------------------
-- Schema
create table if not exists public.preference_levels (
	-- The unique id of the preference level
	id uuid default gen_random_uuid() not null,
	-- The venue this preference level belongs to
	venueid uuid not null,
	-- The label shown to volunteers and editors (e.g., "Preferred", "If necessary", "No")
	label text not null,
	-- The presentation order; lower rank is higher preference (0 = most preferred)
	rank integer not null,
	-- When the level was created
	created_at timestamp with time zone default now() not null
);

alter table only public.preference_levels
add constraint preference_levels_pkey primary key (id);

alter table only public.preference_levels
add constraint preference_levels_venueid_fkey foreign KEY (venueid) references public.venues (id) on delete cascade;

alter table only public.preference_levels
add constraint preference_levels_venue_rank_unique unique (venueid, rank);

alter table only public.preference_levels
add constraint preference_levels_venue_label_unique unique (venueid, label);

alter table only public.preference_levels
add constraint preference_levels_label_check check (char_length(label) > 0);

alter table only public.preference_levels
add constraint preference_levels_rank_check check (rank >= 0);

create index preference_levels_venue_index on public.preference_levels using btree (venueid);

--------------------------------------
-- Security
alter table public.preference_levels OWNER to postgres;

alter table public.preference_levels ENABLE row LEVEL SECURITY;

grant all on table public.preference_levels to anon;

grant all on table public.preference_levels to authenticated;

grant all on table public.preference_levels to service_role;

create policy "authenticated scholars can view preference levels" on public.preference_levels for
select
	to authenticated using (true);

create policy "only admins can create preference levels" on public.preference_levels for INSERT to authenticated
with
	check (public.isAdmin (venueid));

create policy "only admins can update preference levels" on public.preference_levels
for update
	to authenticated using (public.isAdmin (venueid));

create policy "only admins can delete preference levels" on public.preference_levels for DELETE to authenticated using (public.isAdmin (venueid));

alter publication supabase_realtime
add table preference_levels;
