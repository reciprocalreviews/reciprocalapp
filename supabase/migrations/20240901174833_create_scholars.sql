create table public.scholars (
  -- The unique auth ID for scholars, corresponding to an auth record on the auth table in Supabase.
  id uuid not null primary key references auth.users on delete cascade,
  -- The scholar's ORCID, a 16-digit number with dashes conforming to the ISO International Standard Name Identifier (ISNI) format, e.g. 0000-0001-2345-6789. 
  orcid text default null,
  -- The scholar's public name
  name text default null,
  -- The scholar's optional and public preferred email address for review requests
  email text default null,
  -- Whether the scholar is available to review
  available boolean not null default true,
  -- Whether the scholar is a steward
  steward boolean not null default false,
  -- The scholar's explanation of their availabilty
  status text not null default ''::text,
  -- When the scholar joined
  "when" timestamp with time zone not null default now()
);

-- Check if the given scholar is a steward
create function isSteward() 
returns boolean 
language sql
as $$
    select (exists (select id from scholars where id = auth.uid() and steward));
$$;

alter table public.scholars
  enable row level security;

create policy "Scholar can insert themselves" on public.scholars
  for insert to anon, authenticated with check (true);

create policy "Scholar metadata is public" on public.scholars
  for select to anon, authenticated using (true);

create policy "Scholars can be edited by stewards and selves" on public.scholars
  for update to anon, authenticated using (id = auth.uid() or isSteward());

create policy "Scholars can remove themselves" on public.scholars
  for delete to anon, authenticated using (id = auth.uid());


-- Take the new user and insert a row in scholars
create function public.handle_new_scholar()
returns trigger as $$
begin
  -- Insert the new user into the scholars table.
  insert into public.scholars (id, email)
  values (new.id, new.email);
  -- Return the new row.
  return new;
end;
$$ language plpgsql security definer;

-- This trigger automatically creates a profile entry when a new user signs up via Supabase Auth.
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_scholar();
