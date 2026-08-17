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

--------------------------------------
-- Promote or demote a steward.
--
-- `steward` is privilege-bearing, and no client role may write it: the UPDATE
-- grant above is narrowed to (name, available, status, status_time) precisely so
-- a scholar cannot promote themselves. 20260719010000 said the tool for changing
-- it "belongs behind a SECURITY DEFINER RPC gated on isSteward(), not a blanket
-- table privilege". This is that RPC, and it is the only path to the column.
--
-- One function taking a boolean rather than a promote/demote pair: the caller
-- check, the existence check, the lock, and the audit story are identical in both
-- directions, and the asymmetries are two branches. Two entry points would be two
-- owner/revoke/grant trios, two generated type entries, and two copies of the
-- same authorization test.
create or replace function public.set_steward (_scholar uuid, _steward boolean) returns jsonb language plpgsql security definer
set
	search_path='' as $$
declare
	_caller uuid := (select auth.uid());
	_current boolean;
	_remaining integer;
begin
	if _caller is null then
		raise exception 'Authentication required';
	end if;

	-- Lock every steward row, and the target, BEFORE deciding anything. Under READ
	-- COMMITTED each statement takes its own snapshot, so two stewards demoting each
	-- other concurrently would each see the other still standing, and both would
	-- succeed — leaving nobody, in a system where this function is the only way back
	-- to the column. Locking first serializes the function against itself: the second
	-- caller waits, then re-reads committed truth instead of its own stale snapshot.
	-- The lock set is tiny and these calls are rare, so the cost is a brief wait for
	-- a steward editing their own name at the same moment.
	perform 1 from public.scholars where steward or id = _scholar for update;

	-- After the lock, not before, so a caller demoted while it waited is refused.
	if not public.isSteward() then
		raise exception 'Only stewards can change who is a steward' using errcode = 'RR010';
	end if;

	select steward into _current from public.scholars where id = _scholar;
	if not found then
		raise exception 'No such scholar' using errcode = 'RR011';
	end if;

	-- Already so, and saying so is not a failure: the caller may simply be looking at
	-- a list that has moved on. `changed` lets the client tell a no-op from a write
	-- without a check-then-write race against a client-side "are they already?" test.
	if _current = _steward then
		return jsonb_build_object('scholar', _scholar, 'steward', _current, 'changed', false);
	end if;

	if not _steward then
		-- Stepping down is something another steward does for you, so nobody resigns
		-- by accident and a lone steward cannot strand the platform. Checked before
		-- the count, so a sole steward gets this message rather than the confusing
		-- "last steward" one.
		if _scholar = _caller then
			raise exception 'You cannot remove yourself as a steward' using errcode = 'RR013';
		end if;

		-- Unreachable serially — demoting X requires a steward caller other than X, so
		-- one always survives — and not dead code: it fires in the concurrent case the
		-- lock above serializes, where the caller's own stewardship was revoked while
		-- it waited. The guard and the lock only work together.
		select count(*) into _remaining
		from public.scholars
		where steward and id <> _scholar;
		if _remaining = 0 then
			raise exception 'The last steward cannot be demoted' using errcode = 'RR012';
		end if;
	end if;

	update public.scholars set steward = _steward where id = _scholar;

	-- Who did this, and when, is recorded for free: public.scholars is in the
	-- audit_log trigger's table list, and log_audit_event stores auth.uid(), which is
	-- the CALLER — security definer changes the current user, not the JWT claim.
	return jsonb_build_object('scholar', _scholar, 'steward', _steward, 'changed', true);
end;
$$;

alter function public.set_steward (uuid, boolean) OWNER to "postgres";

-- Revoking from `public` also drops service_role's implicit execute, which is
-- correct: service_role keeps table-level UPDATE on scholars from `grant all`
-- above, so the psql recovery path never needs this function.
revoke
execute on function public.set_steward (uuid, boolean)
from
	public,
	anon;

grant
execute on function public.set_steward (uuid, boolean) to authenticated;

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
