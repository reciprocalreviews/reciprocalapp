-- A table of minted tokens.
create table tokens (
  -- The unique ID of the token
  id uuid not null default uuid_generate_v1() primary key,
  -- The currency that the token is in
  currency uuid not null references currencies(id),
  -- The scholar that currently possess the token, or null, representing no one
  scholar uuid references scholars(id),
  -- The venue that currently posses the token, or null
  venue uuid references venues(id),
  -- Require that there is either a scholar or venue owner, but not both
  constraint check_owner check (num_nonnulls(scholar, venue) = 1)
);

-- Make it fast to retrieve the tokens of a scholar, venue, or currency
create index tokens_scholar_index on tokens(scholar);
create index tokens_venue_index on tokens(venue);
create index tokens_currency_index on tokens(currency);

-- Enable RLS for tokens
alter table public.tokens
  enable row level security;

create policy "only minters can create tokens" on public.tokens
  for insert to anon, authenticated with check (auth.uid() = any((select minters from currencies where id = currency)::uuid[]));

create policy "tokens are public" on public.tokens
  for select to anon, authenticated using (true);

create policy "only token owners can update a token" on public.tokens
  for update to anon, authenticated using ((venue is not null and isEditor(venue)) or (scholar is not null and auth.uid() = scholar));

create policy "tokens cannot be deleted" on public.tokens
  for delete to anon, authenticated using (false);


-- A table of transactions, recording a history of token transfers
create table transactions (
  -- The unique ID of the transaction
  id uuid not null default uuid_generate_v1() primary key,
  -- When the transaction was proposed
  created timestamptz not null default now(),
  -- The scholar who gave the tokens
  from_scholar uuid references scholars(id),
  -- The venue who gave the tokens
  from_venue uuid references venues(id),
  -- Require that there is either a scholar or venue source but not both
  constraint check_from check (num_nonnulls(from_scholar, from_venue) = 1),
  -- The scholar who received the tokens,
  to_scholar uuid references scholars(id),
  -- The venue that received the tokens,
  to_venue uuid references venues(id),
  -- Require that there is either a scholar or venue destination but not both
  constraint check_to check (num_nonnulls(to_scholar, to_venue) = 1),
  -- An array of token ids moved in the transaction
  tokens uuid[] not null default '{}'::uuid[],
  -- The currency the amount is in
  currency uuid not null references currencies(id),
  -- The purpose of the transaction
  purpose text not null
);

-- Enable RLS for tokens
alter table public.transactions
  enable row level security;

create policy "only owners can transfer their tokens" on public.transactions
  for insert to anon, authenticated with check (
    (from_scholar is not null and auth.uid() = from_scholar) or 
    (from_venue is not null and (auth.uid() = any((select editors from venues where id = from_venue)::uuid[])))
);

create policy "transactions are only visible to minters and those involved" on public.transactions
  for select to anon, authenticated using (
    (auth.uid() = from_scholar) or 
    (auth.uid() = to_scholar) or 
    (auth.uid() = any((select minters from currencies where id = currency)::uuid[])) or
    (from_venue is not null and auth.uid() = any((select editors from venues where id = from_venue)::uuid[])) or
    (to_venue is not null and auth.uid() = any((select editors from venues where id = to_venue)::uuid[]))
);

create policy "transactions are read only" on public.transactions
  for update to anon, authenticated using (false);

create policy "transactions cannot be deleted" on public.transactions
  for delete to anon, authenticated using (false);
