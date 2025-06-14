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
  for insert to anon, authenticated with check ((select auth.uid()) = any((select minters from currencies where id = currency)::uuid[]));

create policy "tokens are public" on public.tokens
  for select to anon, authenticated using (true);

create policy "only token owners can update a token" on public.tokens
  for update to anon, authenticated 
    using ((venue is not null and isEditor(venue)) or (scholar is not null and (select auth.uid()) = scholar))
    with check (true);

create policy "tokens cannot be deleted" on public.tokens
  for delete to anon, authenticated using (false);

create type transaction_status as enum ('proposed', 'approved', 'canceled');

-- A table of transactions, recording a history of token transfers
create table transactions (
  -- The unique ID of the transaction
  id uuid not null default uuid_generate_v1() primary key,
  -- When the transaction was created
  created timestamptz not null default now(),
  -- The scholar who created the transaction
  creator uuid not null references scholars(id),
  -- The scholar is giving the tokens
  from_scholar uuid references scholars(id),
  -- The venue gaving the tokens
  from_venue uuid references venues(id),
  -- Require that there is either a scholar or venue source but not both
  constraint check_from check (num_nonnulls(from_scholar, from_venue) = 1),
  -- The scholar who received the tokens,
  to_scholar uuid references scholars(id),
  -- The venue that received the tokens,
  to_venue uuid references venues(id),
  -- Require that there is either a scholar or venue destination but not both
  constraint check_to check (num_nonnulls(to_scholar, to_venue) = 1),
  -- An array of token ids moved in the transaction. If the null UUID, then tokens haven't been determined yet.
  tokens uuid[] not null,
  -- The currency the amount is in
  currency uuid not null references currencies(id),
  -- The purpose of the transaction, containing any information necessary for approval of the transaction by the from source
  -- Can also be used to specify the reason for cancelation.
  purpose text not null,
  -- The status of the transaction
  status transaction_status not null
);

-- Enable RLS for tokens
alter table public.transactions
  enable row level security;

create policy "only owners can transfer their tokens if approved" on public.transactions
  for insert to anon, authenticated with check (
    status = 'proposed' or
    (
      status = 'approved' and
      (
        (from_scholar is not null and (select auth.uid()) = from_scholar) or 
        (from_venue is not null and ((select auth.uid()) = any((select editors from venues where id = from_venue)::uuid[])))
      )
    )
);

create policy "transactions are only visible to minters and those involved" on public.transactions
  for select to anon, authenticated using (
    ((select auth.uid()) = from_scholar) or 
    ((select auth.uid()) = to_scholar) or 
    ((select auth.uid()) = any((select minters from currencies where id = currency)::uuid[])) or
    (from_venue is not null and (select auth.uid()) = any((select editors from venues where id = from_venue)::uuid[])) or
    (to_venue is not null and (select auth.uid()) = any((select editors from venues where id = to_venue)::uuid[]))
);

create policy "only the giver and minters can update transactions" on public.transactions
  for update to anon, authenticated using (
    ((select auth.uid()) = from_scholar) or 
    ((select auth.uid()) = any((select minters from currencies where id = currency)::uuid[])) or
    (from_venue is not null and (select auth.uid()) = any((select editors from venues where id = from_venue)::uuid[]))
  );

create policy "transactions cannot be deleted" on public.transactions
  for delete to anon, authenticated using ((select auth.uid()) = any((select minters from currencies where id = currency)::uuid[]));
