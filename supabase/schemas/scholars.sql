--------------------------------------
-- TABLE
-- Represents an individual researcher.
create table if not exists public.scholars (
	-- The unique auth ID for scholars, corresponding to an auth record on the auth table in Supabase.
	id uuid not null,
	-- The scholar's ORCID, a 16-digit number with dashes conforming to the ISO International Standard Name Identifier (ISNI) format, e.g. 0000-0001-2345-6789. 
	orcid text,
	-- The scholar's public name
	name text,
	-- The scholar's optional and public preferred email address for review requests
	email text,
	-- Whether the scholar is available to review
	available boolean default true not null,
	-- Whether the scholar is a steward
	steward boolean default false not null,
	-- The scholar's explanation of their availabilty
	status text default ''::text not null,
	-- When the scholar joined
	created_at timestamp with time zone default now() not null,
	-- The time the scholar last updated their status
	status_time timestamp with time zone,
	-- The last time the scholar was reminded about their status
	status_reminder_time timestamp with time zone
);

grant all on table public.scholars to "anon";

grant all on table public.scholars to "authenticated";

grant all on table public.scholars to "service_role";

alter table public.scholars OWNER to "postgres";

alter table only public.scholars
add constraint "scholars_pkey" primary key ("id");

alter table only public.scholars
add constraint "scholars_id_fkey" foreign KEY ("id") references auth.users ("id") on delete cascade;

--------------------------------------
-- FUNCTIONS
create or replace function public.isSteward () RETURNS boolean LANGUAGE "sql" SECURITY DEFINER
set
	"search_path" to '' as $$
    select (exists (select id from public.scholars where id = (select auth.uid()) and steward));
$$;

alter function public.isSteward () OWNER to "postgres";

grant all on FUNCTION public.isSteward () to "anon";

grant all on FUNCTION public.isSteward () to "authenticated";

grant all on FUNCTION public.isSteward () to "service_role";

create or replace function public.handle_new_scholar () RETURNS "trigger" LANGUAGE "plpgsql" SECURITY DEFINER
set
	"search_path" to '' as $$
begin
  -- Insert the new user into the scholars table.
  insert into public.scholars (id, email)
  values (new.id, new.email);
  -- Return the new row.
  return new;
end;
$$;

alter function public.handle_new_scholar () OWNER to "postgres";

grant all on FUNCTION public.handle_new_scholar () to "anon";

grant all on FUNCTION public.handle_new_scholar () to "authenticated";

grant all on FUNCTION public.handle_new_scholar () to "service_role";

--------------------------------------
-- SECURITY
alter table public.scholars ENABLE row LEVEL SECURITY;

create policy "Scholar can insert themselves" on public.scholars for INSERT to "authenticated",
"anon"
with
	check (true);

create policy "Scholar metadata is public" on public.scholars for
select
	to "authenticated",
	"anon" using (true);

create policy "Scholars can be edited by stewards and selves" on public.scholars
for update
	to "authenticated",
	"anon" using (
		(
			(
				"id"=(
					select
						auth.uid () as "uid"
				)
			)
			or public.isSteward ()
		)
	);

create policy "Scholars can remove themselves" on public.scholars for DELETE to "authenticated",
"anon" using (
	(
		"id"=(
			select
				auth.uid () as "uid"
		)
	)
);
