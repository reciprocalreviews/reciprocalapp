--------------------------------------
-- Schema
-- A table of minted tokens.
create table if not exists public.tokens (
	-- The unique ID of the token
	id uuid default gen_random_uuid() not null,
	-- The currency that the token is in
	currency uuid not null,
	-- The scholar that currently possess the token, or null, representing no one
	scholar uuid,
	-- The venue that currently posses the token, or null
	venue uuid,
	-- Require that there is either a scholar or venue owner, but not both
	constraint "check_owner" check ((num_nonnulls (scholar, venue)=1))
);

alter table public.tokens OWNER to "postgres";

alter table only public.tokens
add constraint tokens_pkey primary key (id);

alter table only public.tokens
add constraint tokens_currency_fkey foreign KEY (currency) references public.currencies (id);

alter table only public.tokens
add constraint tokens_scholar_fkey foreign KEY (scholar) references public.scholars (id);

alter table only public.tokens
add constraint tokens_venue_fkey foreign KEY (venue) references public.venues (id);

--------------------------------------
-- Indexes
create index tokens_currency_index on public.tokens using btree (currency);

create index tokens_scholar_index on public.tokens using btree (scholar);

create index tokens_venue_index on public.tokens using btree (venue);

--------------------------------------
-- Security
alter table public.tokens ENABLE row LEVEL SECURITY;

create policy "tokens are public" on public.tokens for
select
	to authenticated,
	anon using (true);

create policy "only minters can create tokens" on public.tokens for INSERT to authenticated,
anon
with
	check (
		(
			(
				select
					auth.uid () as uid
			)=any (
				(
					select
						currencies.minters
					from
						public.currencies
					where
						(currencies.id=tokens.currency)
				)::uuid[]
			)
		)
	);

create policy "only token owners and venue admins can update a token" on public.tokens
for update
	to authenticated using (
		(
			(
				(venue is not null)
				and public.isAdmin (venue)
			)
			or (
				(scholar is not null)
				and (
					(
						select
							auth.uid () as uid
					)=scholar
				)
			)
		)
	)
with
	check (true);

create policy "tokens cannot be deleted" on public.tokens for DELETE to authenticated,
anon using (false);

grant all on table public.tokens to anon;

grant all on table public.tokens to authenticated;

grant all on table public.tokens to service_role;

alter publication supabase_realtime
add table tokens;
