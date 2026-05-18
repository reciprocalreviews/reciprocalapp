--------------------------------------
-- preference_levels: venue-configurable, ordered preference labels a volunteer
-- can pick from when committing to a role (e.g., "Preferred", "If necessary").
create table if not exists public.preference_levels (
	id uuid default gen_random_uuid() not null,
	venueid uuid not null,
	label text not null,
	rank integer not null,
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

alter table public.preference_levels OWNER to postgres;

alter table public.preference_levels ENABLE row LEVEL SECURITY;

grant all on table public.preference_levels to anon;

grant all on table public.preference_levels to authenticated;

grant all on table public.preference_levels to service_role;

create policy "anyone can view preference levels" on public.preference_levels for
select
	to authenticated,
	anon using (true);

create policy "only admins can create preference levels" on public.preference_levels for INSERT to authenticated
with
	check (public.isAdmin (venueid));

create policy "only admins can update preference levels" on public.preference_levels
for update
	to authenticated using (public.isAdmin (venueid));

create policy "only admins can delete preference levels" on public.preference_levels for DELETE to authenticated using (public.isAdmin (venueid));

alter publication supabase_realtime
add table preference_levels;

--------------------------------------
-- volunteers: add papers (soft cap; null = unspecified).
alter table public.volunteers
add column papers integer;

alter table public.volunteers
add constraint volunteers_papers_check check (papers is null or papers >= 0);

--------------------------------------
-- assignments: add preferenceid for per-bid ranked preference (#122).
-- Meaningful only on bid rows; null otherwise. on delete set null preserves
-- the bid record if the venue retires the level.
alter table public.assignments
add column preferenceid uuid;

alter table public.assignments
add constraint assignments_preferenceid_fkey foreign KEY (preferenceid) references public.preference_levels (id) on delete set null;
