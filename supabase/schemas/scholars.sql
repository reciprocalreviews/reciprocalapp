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

-- Restrict which columns a scholar may write. The update policy below authorizes the ROW
-- but not individual columns, so without this a scholar could self-promote via `steward`,
-- claim another researcher's `orcid`, or set `email` directly and bypass contact-email
-- verification (#27) — the invariant that scholars.email holds only a VERIFIED address.
-- A column-level revoke is ineffective while authenticated holds the TABLE-level UPDATE
-- granted by `grant all` above, so remove that and re-grant only the editable columns.
-- `email` is written solely by public.verify_email and `status_reminder_time` solely by
-- the remind edge function, both of which bypass these grants.
revoke
update on public.scholars
from
	authenticated,
	anon;

grant
update (name, available, status, status_time) on public.scholars to authenticated;

alter table public.scholars OWNER to "postgres";

alter table only public.scholars
add constraint "scholars_pkey" primary key ("id");

alter table only public.scholars
add constraint "scholars_id_fkey" foreign KEY ("id") references auth.users ("id") on delete cascade;

-- One ORCID iD identifies exactly one scholar (#87). Partial, because a scholar row
-- created outside the ORCID flow (tests, fixtures) may legitimately have no iD yet.
create unique index if not exists scholars_orcid_unique on public.scholars (orcid)
where
	orcid is not null;

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

create or replace function public.handle_new_scholar () returns "trigger" language "plpgsql" security definer
set
	"search_path" to '' as $$
begin
  insert into public.scholars (id, orcid, name)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data->>'orcid',
      new.raw_user_meta_data->>'provider_id',
      new.raw_user_meta_data->>'sub'
    ),
    -- ORCID sends given_name/family_name and no `name`. Prefer `name` for providers that do
    -- send it; fall back to the composed form. Left null when the provider sends neither,
    -- so the scholar can supply one rather than being given a placeholder.
    coalesce(
      nullif(btrim(new.raw_user_meta_data->>'name'), ''),
      nullif(btrim(concat_ws(' ',
        new.raw_user_meta_data->>'given_name',
        new.raw_user_meta_data->>'family_name'
      )), '')
    )
  );
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

create policy "Scholars cannot be inserted except by platform" on public.scholars for INSERT to authenticated
with
	check (false);

create policy "Scholar metadata is public" on public.scholars for
select
	to authenticated,
	anon using (true);

create policy "Scholars can be edited by stewards and selves" on public.scholars
for update
	to authenticated using (
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

create policy "Scholars can remove themselves" on public.scholars for DELETE to authenticated using (
	(
		"id"=(
			select
				auth.uid () as "uid"
		)
	)
);

alter publication supabase_realtime
add table scholars;

--------------------------------------
-- The trigger that makes a scholar exist at all. Defined in migration
-- 20240901174833_scholars.sql and long absent from this file, which is how a
-- reader could conclude scholars were created by the application: they are not —
-- inserting one is forbidden by policy, and this is the only path.
create or replace trigger on_auth_user_created
after insert on auth.users for each row
execute procedure public.handle_new_scholar ();
