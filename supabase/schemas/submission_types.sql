/* SCHEMA  */
-- The types of submissions that a venue accepts, including resubmission types.
create table if not exists submission_types (
	-- The unique ID of the submission type
	id uuid not null default gen_random_uuid() primary key,
	-- The venue to which the submission type corresponds
	venue uuid not null references venues (id) on delete cascade,
	-- The submission type that this type is a resubmission of, if applicable
	revision_of uuid default null references submission_types (id) on delete cascade,
	-- The type of the submission, such as "research paper", "research - resubmssion"
	name text not null default ''::text,
	-- A longer description of the submission type, such as "a new research paper submission"
	description text not null default ''::text
);

alter table public.submission_types OWNER to "postgres";

grant all on table public.submission_types to "anon";

grant all on table public.submission_types to "authenticated";

grant all on table public.submission_types to "service_role";

--------------------------------------
-- Indexes
create index submission_types_venue_index on public.submission_types using btree (venue);

--------------------------------------
-- Security
alter table public.submission_types ENABLE row LEVEL SECURITY;

-- Venue admins can create submission types for their venue, and delete them if they are not in use.
create policy "venue admins can create submission types" on public.submission_types for INSERT to authenticated
with
	check (public.isAdmin (venue));

-- Anyone can see submission types for a venue
create policy "anyone can read submission types" on public.submission_types for
select
	to authenticated using (true);

-- Venue admins can update submission types for their venue.
create policy "venue admins can update submission types" on public.submission_types
for update
	to authenticated using (public.isAdmin (venue))
with
	check (true);

-- Venue admins can delete submission types for their venue.
create policy "venue admins can delete submission types" on public.submission_types for DELETE to authenticated using (public.isAdmin (venue));

alter publication supabase_realtime
add table submission_types;
