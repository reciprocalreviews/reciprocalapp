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
  welcome_amount integer not null,
  -- Submission cost in the venue's currency
  submission_cost integer not null default 0,
  -- Whether the the venue permits public bidding on submissions
  bidding boolean not null default true,
  -- One or more scholars who serve as editors of the venue
  editors uuid[] not null default '{}'::uuid[] check (cardinality(editors) > 0)
);

alter table public.venues
  enable row level security;

create policy "only stewards can create venues" on public.venues
  for insert to anon, authenticated with check (isSteward());

create policy "anyone can view venues" on public.venues
  for select to anon, authenticated using (true);

create policy "stewards and editors can update venues" on public.venues
  for update to anon, authenticated using (isSteward() or auth.uid() = any(editors));

create policy "stewards and editors can delete venues" on public.venues
  for delete to anon, authenticated using (isSteward() or auth.uid() = any(editors));

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
  invited boolean not null,
  -- The token compensation for a commitment, in the venue's currency
  amount integer not null
);

create index roles_venue_index on roles(venueid);

-- Check if the given scholar is an stewards
create function isEditor("_venueid" uuid) 
returns boolean
language sql
as $$
    select (auth.uid() = any((select editors from venues where id = _venueid)::uuid[]));
$$;

alter table public.roles
  enable row level security;

-- only editors can create venue roles
create policy "only editors can create venue roles" on public.roles
  for insert to anon, authenticated with check (isEditor(venueid));

-- anyone can view roles
create policy "anyone can view roles" on public.roles
  for select to anon, authenticated using (true);

-- only editors can update roles
create policy "only editors can update roles" on public.roles
  for update to anon, authenticated using (isEditor(venueid));

-- only editors can delete roles
create policy "only editors can delete roles" on public.roles
  for delete to anon, authenticated using (isEditor(venueid));

create type invited as enum ('invited', 'accepted', 'declined');

-- editors can invite and volunteers if not invite only
-- anyone can view volunteers
-- only volunteers can update
-- editors and volunteers can delete
create table volunteers (
  -- The unique id of the role
  id uuid not null default uuid_generate_v1() primary key,
  -- The id of the scholar who volunteered
  scholarid uuid not null references scholars(id) on delete cascade,
  -- The role they volunteered for
  roleid uuid not null references roles(id) on delete cascade,
  -- When this record was last updated
  created timestamp with time zone not null default now(),
  -- Relevant expertise provided by the scholar for the role
  expertise text not null,
  -- If the volunteer role is active or inactive, allowing scholars to unvolunteer, then revolunteer.
  -- Allows us to keep the record of volunteering without granting newcomer tokens more than once.
  active boolean not null default true,
  -- Whether this role as been accepted by the scholar
  accepted invited not null default 'accepted'
);

create index scholar_volunteer_index on volunteers(scholarid);
create index role_volunteer_index on volunteers(roleid);

alter table public.volunteers
  enable row level security;

create policy "editors can invite and volunteers if not invite only" on public.volunteers
  for insert to anon, authenticated with check (
    isEditor((select venueid from roles where id = roleid)) or 
    (auth.uid() = scholarid and not (select invited from roles where id = roleid))
    );

create policy "anyone can view volunteers" on public.volunteers
  for select to anon, authenticated using (true);

create policy "volunteers can update" on public.volunteers
  for update to anon, authenticated using (auth.uid() = scholarid);

create policy "editors and volunteers can delete" on public.volunteers
  for delete to anon, authenticated using (isEditor((select venueid from roles where id = roleid)) or auth.uid() = scholarid);

-- anyone can propose venues
-- anyone can view proposals
-- stewards can update proposals
-- stewards can delete proposals
create table proposals (
  -- The unique ID of the venue
  id uuid not null default uuid_generate_v1() primary key,
  -- The title of the venue
  title text not null default ''::text,
  -- A link to the venue's official web page
  url text not null default ''::text,  
  -- The email addresses of editors responsible for the venue
  editors text[] not null default '{}'::text[],
  -- The estimated size of the research community,
  census integer not null,
  -- If set, corresponds to the venue created upon approval.
  venue uuid references venues(id) default null
);

alter table public.proposals
  enable row level security;

create policy "anyone can propose venues" on public.proposals
  for insert to anon, authenticated with check (true);

create policy "anyone can view proposals" on public.proposals
  for select to anon, authenticated using (true);

create policy "admins can update proposals" on public.proposals
  for update to anon, authenticated using (isSteward());

create policy "admins can delete proposals" on public.proposals
  for delete to anon, authenticated using (isSteward());

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
    proposalid uuid not null references proposals(id) on delete cascade,
    -- When this record was last updated
    created timestamp with time zone not null default now()
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

