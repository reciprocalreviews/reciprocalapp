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
	-- The id of the currency the venue is currently using
	currency uuid not null,
	-- The optional amount of newly minted tokens granted to new volunteers
	welcome_amount integer not null,
	-- Submission cost in the venue's currency
	submission_cost integer default 0 not null,
	-- One or more scholars who serve as admins of the venue
	admins uuid[] default '{}'::uuid[] not null,
	-- Whether the venue is active; null if so, text if not, explaining why.
	inactive text default 'This venue is being configured.'::text,
	-- Whether assignments are visible to conflicted scholars (open reviewing)
	anonymous_assignments boolean default true not null,
	-- There must be at least one admin
	constraint venues_admins_check check (cardinality(admins)>0)
);

alter table only public.venues
add constraint venues_pkey primary key (id);

alter table only public.venues
add constraint venues_currency_fkey foreign KEY (currency) references public.currencies (id);

alter table public.venues OWNER to "postgres";

--------------------------------------
-- Functions
create or replace function public.isAdmin (_venueid uuid) RETURNS boolean LANGUAGE sql SECURITY DEFINER
set
	"search_path" to '' as $$
    select ((select auth.uid()) = any((select admins from public.venues where id = _venueid)::uuid[]));
$$;

alter function public.isAdmin (_venueid uuid) OWNER to postgres;

grant all on FUNCTION public.isAdmin (_venueid uuid) to anon;

grant all on FUNCTION public.isAdmin (_venueid uuid) to authenticated;

grant all on FUNCTION public.isAdmin (_venueid uuid) to service_role;

create or replace function public.no_minter_admins () RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
set
	"search_path" to '' as $$
begin
    -- If the admin of this venue is a minter of its currency, raise an exception
    if new.admins && (select minters from public.currencies where id = new.currency) then
        raise exception 'A venue admin cannot be the minter of the venue currency';
    end if;
    return new;
end;
$$;

alter function public.no_minter_admins () OWNER to "postgres";

grant all on FUNCTION public.no_minter_admins () to "anon";

grant all on FUNCTION public.no_minter_admins () to "authenticated";

grant all on FUNCTION public.no_minter_admins () to "service_role";

--------------------------------------
-- Security
alter table public.venues ENABLE row LEVEL SECURITY;

create policy "anyone can view venues" on public.venues for
select
	to "authenticated",
	"anon" using (true);

create policy "only stewards can create venues" on public.venues for INSERT to "authenticated",
"anon"
with
	check (public.isSteward ());

create policy "stewards and admins can update venues" on public.venues
for update
	to "authenticated",
	"anon" using (
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

create policy "stewards and admins can delete venues" on public.venues for DELETE to "authenticated",
"anon" using (
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

grant all on table public.venues to "anon";

grant all on table public.venues to "authenticated";

grant all on table public.venues to "service_role";

--------------------------------------
-- Trigger
create or replace trigger no_minter_admins BEFORE INSERT
or
update on public.venues for EACH row
execute FUNCTION public.no_minter_admins ();

alter publication supabase_realtime
add table venues;
