-- Add a status on scholars that gives them admin privileges on the platform, including permission to create new venues.
alter table public.scholars add column administrator boolean not null default false;

-- Check if the given scholar is an administrator
create function isAdmin() 
returns boolean 
language sql
as $$
    select (exists (select id from scholars where id = auth.uid() and administrator));
$$;

create table venues (
  -- The unique ID of the venue
  id uuid not null default uuid_generate_v1() primary key,
  -- The title of the venue
  title text not null default ''::text,
  -- The description of the venue
  description text not null default ''::text,
  -- A link to the venue's official web page
  url text not null default ''::text,
  -- The id of the currency the venue is currently using
  currency uuid not null references currencies(id),
  -- The optional amount of newly minted tokens granted to new volunteers
  welcome_amount integer,
  -- Whether the the venue permits public bidding on submissions
  bidding boolean not null default true,
  -- One or more scholars who serve as editors of the venue
  editors uuid[] not null default '{}'::uuid[] check (cardinality(editors) > 0)
);

alter table public.venues
  enable row level security;

create policy "only administrators can create venues" on public.venues
  for insert to anon, authenticated with check (isAdmin());

create policy "anyone can view venues" on public.venues
  for select to anon, authenticated using (true);

create policy "admins and editors can update venues" on public.venues
  for update to anon, authenticated using (isAdmin() or auth.uid() = any(editors));

create policy "admins and editors can delete venues" on public.venues
  for delete to anon, authenticated using (isAdmin() or auth.uid() = any(editors));

-- only editors can create venue roles
-- anyone can view roles
-- only editors can update roles
-- only editors can delete roles
create table roles (
  -- The unique id of the role
  id uuid not null default uuid_generate_v1() primary key,
  -- The ID of the venue
  venueid uuid not null references venues(id) on delete cascade,
  -- The name of the role
  name text not null default ''::text,
  -- The rich text description of the role
  description text not null default ''::text,
  -- Whether the role is invite only
  invited boolean not null
);

create unique index roles_venue_index on roles(venueid);

-- Check if the given scholar is an administrator
create function isEditor("_venueid" uuid) 
returns boolean 
language sql
as $$
    select (exists (select id from venues where auth.uid() = any(editors)));
$$;

alter table public.roles
  enable row level security;

create policy "only editors can create venue roles" on public.roles
  for insert to anon, authenticated with check (isEditor(venueid));

create policy "anyone can view roles" on public.roles
  for select to anon, authenticated using (true);

create policy "only editors can update roles" on public.roles
  for update to anon, authenticated using (isEditor(venueid));

create policy "only editors can delete roles" on public.roles
  for delete to anon, authenticated using (isEditor(venueid));

-- only editors can create commitments
-- only editors can update commitments
-- anyone can view commitments
-- only editors can delete commitments
create table commitments (
  -- The unique id of the commitment
  id uuid not null default uuid_generate_v1() primary key,
  -- The ID of the venue
  venueid uuid not null references venues(id) on delete cascade,
  -- The label for the commitment
  label text not null,
  -- The token compensation for a commitment, in the venue's currency
  amount integer not null
);

create unique index commitments_venue_index on commitments(venueid);

alter table public.commitments
  enable row level security;

create policy "only editors can create commitments" on public.commitments
  for insert to anon, authenticated with check (isEditor(venueid));

create policy "anyone can view commitments" on public.commitments
  for select to anon, authenticated using (true);

create policy "only editors can update commitments" on public.commitments
  for update to anon, authenticated using (isEditor(venueid));

create policy "only editors can delete commitments" on public.commitments
  for delete to anon, authenticated using (isEditor(venueid));

-- editors can invite and volunteers if not invite only
-- anyone can view volunteers
-- only volunteers can update
-- editors and volunteers can delete
create table volunteers (
  -- The id of the scholar who volunteered
  scholarid uuid not null references scholars(id) on delete cascade,
  -- The role they volunteered for
  roleid uuid not null references roles(id) on delete cascade,
  -- The id of the venue volunteered for
  venueid uuid not null references venues(id) on delete cascade,
  -- The commitment they made
  committment uuid not null references commitments(id) on delete cascade,
  -- When this record was last updated
  created timestamp with time zone not null default now(),
  -- Relevant expertise provided by the scholar for the role
  expertise text not null,
  -- Optionally, how many submissions they wish to review in the role
  count integer default null
);

create unique index venue_volunteer_index on volunteers(venueid);
create unique index scholar_volunteer_index on volunteers(scholarid);
create unique index role_volunteer_index on volunteers(roleid);

alter table public.volunteers
  enable row level security;

create policy "editors can invite and volunteers if not invite only" on public.volunteers
  for insert to anon, authenticated with check (
    isEditor(venueid) or 
    (auth.uid() = scholarid and (select invited from roles where id = roleid))
    );

create policy "anyone can view volunteers" on public.volunteers
  for select to anon, authenticated using (true);

create policy "volunteers can update" on public.volunteers
  for update to anon, authenticated using (auth.uid() = scholarid);

create policy "editors and volunteers can delete" on public.volunteers
  for delete to anon, authenticated using (isEditor(venueid) or auth.uid() = scholarid);

-- anyone can propose venues
-- anyone can view proposals
-- admins can update proposals
-- admins can delete proposals
create table proposals (
  -- The unique ID of the venue
  id uuid not null default uuid_generate_v1() primary key,
  -- The title of the venue
  title text not null default ''::text,
  -- The email addresses of editors responsible for the venue
  editors text[] not null default '{}'::text[],
  -- The estimated size of the research community,
  census integer not null
);

alter table public.proposals
  enable row level security;

create policy "anyone can propose venues" on public.proposals
  for insert to anon, authenticated with check (true);

create policy "anyone can view proposals" on public.proposals
  for select to anon, authenticated using (true);

create policy "admins can update proposals" on public.proposals
  for update to anon, authenticated using (isAdmin());

create policy "admins can delete proposals" on public.proposals
  for delete to anon, authenticated using (isAdmin());

-- anyone can support proposals
-- anyone can view supporters
-- supporters can update support
-- supports can stop supporting
create table supporters (
    -- The unique ID of the support
    id uuid not null default uuid_generate_v1() primary key,
    -- The scholar supporting the proposal
    scholarid uuid not null references scholars(id) on delete cascade,
    -- The message the scholar supported
    message text not null default ''::text,
    -- The proposal being supported
    proposalid uuid not null references proposals(id) on delete cascade
);

alter table public.supporters
  enable row level security;

create policy "anyone can support proposals" on public.supporters
  for insert to anon, authenticated with check (true);

create policy "anyone can view supporters" on public.supporters
  for select to anon, authenticated using (true);

create policy "admins can update proposals" on public.supporters
  for update to anon, authenticated using (auth.uid() = scholarid);

create policy "supporters can stop supporting" on public.supporters
  for delete to anon, authenticated using (auth.uid() = scholarid);

