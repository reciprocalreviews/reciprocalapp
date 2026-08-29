--------------------------------------
-- Schema
create table if not exists public.venues (
	-- The unique ID of the venue
	id uuid default gen_random_uuid() not null,
	-- The title of the venue
	title text default ''::text not null,
	-- The description of the venue
	description text default ''::text not null,
	-- A link to the venue's official web page
	url text default ''::text not null,
	-- The venue's web address: the path segment it is reached by, in place of its id.
	-- Null until the venue chooses one. Released the moment it is changed — nothing
	-- reserves a former address, so links to it break.
	slug text,
	-- The id of the currency the venue is currently using
	currency uuid not null,
	-- The optional amount of newly minted tokens granted to new volunteers
	welcome_amount integer not null,
	-- Whether the venue operates without payment, hiding all token, currency,
	-- cost, and compensation UI. The venue still has a (hidden) currency.
	payment_free boolean default false not null,
	-- One or more scholars who serve as admins of the venue
	admins uuid[] default '{}'::uuid[] not null,
	-- Whether the venue is active; null if so, text if not, explaining why.
	inactive text default 'This venue is being configured.'::text,
	-- Whether assignments are visible to conflicted scholars (open reviewing)
	anonymous_assignments boolean default true not null,
	-- Whether author thank-you notes to reviewers (#22) must be approved by a
	-- venue admin / editor before reviewers see them. Default on.
	vet_thanks boolean default true not null,
	-- How many days after a submission is marked done it remains visible
	-- in the submissions list (sorted to the bottom). 0 hides immediately.
	done_visibility_days integer default 30 not null,
	-- How often, in days, to email admins and minters about this venue's
	-- unapproved proposed transactions. 0 disables reminders for this venue.
	-- The remind edge function gates by this column daily.
	transaction_reminder_frequency_days integer default 0 not null,
	-- When the most recent transaction reminder batch was sent for this venue.
	-- Null means no reminders have been sent yet.
	transaction_reminder_time timestamp with time zone,
	-- There must be at least one admin
	constraint venues_admins_check check (cardinality(admins)>0),
	-- Four characters minimum: three-letter acronyms are the ones most likely to be
	-- contested, and handing the first arrival a name a dozen communities have equal claim
	-- to is not a race worth running. Lowercase only, so an address is the same address
	-- however it is typed. And never a UUID's shape: the resolver decides which column to
	-- query by looking at the segment, and `[a-z][a-z0-9-]*` alone admits one.
	constraint venues_slug_check check (
		slug is null
		or (
			slug~'^[a-z][a-z0-9]*(-[a-z0-9]+)*$'
			and length(slug) between 4 and 40
			and slug!~'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
		)
	),
	-- Bound the visibility window to a year
	constraint venues_done_visibility_days_check check (
		done_visibility_days>=0
		and done_visibility_days<=365
	),
	-- Bound reminder frequency to once-a-day through every-90-days
	constraint venues_transaction_reminder_frequency_days_check check (
		transaction_reminder_frequency_days>=0
		and transaction_reminder_frequency_days<=90
	)
);

alter table only public.venues
add constraint venues_pkey primary key (id);

-- Globally unique, and null is not a value: a btree unique index treats nulls as distinct,
-- so every venue that has not chosen an address coexists with every other.
create unique index if not exists venues_slug_key on public.venues (slug);

alter table only public.venues
add constraint venues_currency_fkey foreign KEY (currency) references public.currencies (id);

alter table public.venues OWNER to "postgres";

--------------------------------------
-- Functions
create or replace function public.isAdmin (_venueid uuid) RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE
set
	"search_path" to '' as $$
    select ((select auth.uid()) = any((select admins from public.venues where id = _venueid)::uuid[]));
$$;

alter function public.isAdmin (_venueid uuid) OWNER to postgres;

grant all on FUNCTION public.isAdmin (_venueid uuid) to anon;

grant all on FUNCTION public.isAdmin (_venueid uuid) to authenticated;

grant all on FUNCTION public.isAdmin (_venueid uuid) to service_role;

-- Only the TRANSITION to active is guarded, not the state. A blanket "active implies an
-- address" constraint would be true of the data we want but false of the data we have:
-- every venue already live has no address, and such a rule would refuse every subsequent
-- edit to it — title, compensation, roles — until someone renamed it. Guarding the
-- transition asks for an address at the one moment an admin is already deciding to
-- publish, and leaves a running venue alone.
create or replace function public.venue_needs_address_to_activate () RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
set
	"search_path" to '' as $$
begin
	if new.inactive is null and old.inactive is not null and new.slug is null then
		raise exception 'A venue needs a web address before it can be activated' using errcode = 'RR016';
	end if;
	return new;
end;
$$;

alter function public.venue_needs_address_to_activate () OWNER to postgres;

create trigger venue_needs_address_to_activate
before update on public.venues for each row
execute function public.venue_needs_address_to_activate ();

--------------------------------------
-- Security
alter table public.venues ENABLE row LEVEL SECURITY;

create policy "anyone can view venues" on public.venues for
select
	to authenticated,
	anon using (true);

create policy "only stewards can create venues" on public.venues for INSERT to authenticated
with
	check (public.isSteward ());

create policy "stewards and admins can update venues" on public.venues
for update
	to authenticated using (
		(
			public.isSteward ()
			or (
				(
					select
						auth.uid () as "uid"
				)=any (admins)
			)
		)
	);

-- No client path deletes a venue: deletion would cascade away its roles,
-- volunteers, assignments, compensation, preference levels, and thanks.
-- service_role keeps its grant for administrative and recovery work.
create policy "venues cannot be deleted" on public.venues for DELETE to authenticated using (false);

grant all on table public.venues to "anon";

grant all on table public.venues to "authenticated";

grant all on table public.venues to "service_role";

-- `grant all` above confers TABLE-level DELETE that the deny policy alone
-- cannot subtract for a caller with a permissive policy elsewhere, so remove it.
revoke delete on public.venues
from
	authenticated,
	anon;

alter publication supabase_realtime
add table venues;
