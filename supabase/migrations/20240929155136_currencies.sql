create table currencies (
  -- The unique id of the currency
  id uuid not null default uuid_generate_v1() primary key,
  -- The name of the currency
  name text not null default ''::text,
  -- The minters of the currency, corresponding to scholar is in the scholars table. Must be at least one minter.
  minters uuid[] not null default '{}'::uuid[] check (cardinality(minters) > 0)
);

alter table public.currencies
  enable row level security;

create policy "anyone can create currencies" on public.currencies
  for insert to anon, authenticated with check (true);

create policy "anyone can view currencies" on public.currencies
  for select to anon, authenticated using (true);

create policy "minters can update currencies" on public.currencies
  for update to anon, authenticated using (auth.uid() = any(minters));

create policy "minters can delete currencies" on public.currencies
  for delete to anon, authenticated using (auth.uid() = any(minters));


-- Three types of exchanges to propose
create type exchange_proposal_kind as enum ('create', 'modify', 'merge');

-- Agreements between owners of currencies
create table exchanges (
  -- The unique id of the currency
  id uuid not null default uuid_generate_v1() primary key,
  -- The time the exchange was created
  proposed timestamp with time zone not null default now(),
  -- Whether the minters have approved. Only set when all current active minters have approved.
  approved timestamp with time zone default null,
  -- The first currency of the exchange
  currency_from uuid not null references currencies(id),
  -- The second currenty of the exchange
  currency_to uuid not null references currencies(id),
  -- The multiplier to convert from currency_from to currency_to
  ratio decimal	not null,
  -- List of minters who have approved
  approvers uuid[] not null default '{}'::uuid[],
  -- The kind of exchange
  kind exchange_proposal_kind
);

create unique index from_index on exchanges(currency_from);
create unique index to_index on exchanges(currency_to);

alter table public.exchanges
  enable row level security;

-- Check if the given scholar is a minter of the given currency
create function isMinter("_scholarid" uuid, "_currencyid" uuid) 
returns boolean 
language sql
as $$
    select (exists (select id from currencies where id = _currencyid and auth.uid() = any(minters)));
$$;

create policy "only minters can create exchanges" on public.exchanges
  for insert to anon, authenticated with check (isMinter(auth.uid(), currency_from) or isMinter(auth.uid(), currency_to));

create policy "anyone can view exchanges" on public.exchanges
  for select to anon, authenticated using (true);

create policy "only minters can update exchanges" on public.exchanges
  for update to anon, authenticated using (isMinter(auth.uid(), currency_from) or isMinter(auth.uid(), currency_to));

create policy "only minters can delete exchanges" on public.exchanges
  for delete to anon, authenticated using (isMinter(auth.uid(), currency_from) or isMinter(auth.uid(), currency_to));