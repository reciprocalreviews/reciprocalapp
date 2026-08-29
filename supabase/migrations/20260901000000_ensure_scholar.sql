-- Make a missing scholar row recoverable.
--
-- A scholar row has exactly one creation path: the on_auth_user_created trigger on
-- auth.users, which fires once, at signup. Nothing else may insert one — the INSERT
-- policy is `with check (false)` — and nothing re-runs the trigger for an account that
-- already exists. So if it does not fire, the account is permanently unusable, and
-- silently: the Supabase session is valid and RLS sees auth.uid(), but the app reads
-- its signed-in scholar from public.scholars, finds nothing, and treats the person as
-- anonymous. The expired-session redirect does not catch it either, since that is gated
-- on the absence of a user id and the user id is present. Signing in again changes
-- nothing, because auth.users already has the row.
--
-- This is not hypothetical. On production a scholar's first ORCID sign-in created their
-- auth.users row, redirected them to /scholar/<their id> as it is supposed to, and the
-- page reported that it could not load a profile that had never been created.
--
-- Two functions, and a third rewritten to share with them:
--
--   scholar_identity  the (orcid, name) a scholar row starts life with, given the OIDC
--                     metadata of the account behind it. Factored out so the trigger and
--                     the repair cannot disagree about it. They nearly did once already:
--                     20260720010000 fixed a `name` read that ORCID never sends, and
--                     backfilled every null it had produced.
--   handle_new_scholar  unchanged in behavior; now calls the above.
--   ensure_scholar    creates the caller's own missing row. Callable by `authenticated`
--                     and nobody else, and it takes no arguments — the row it creates is
--                     always auth.uid()'s, so there is nothing to pass and no way to
--                     aim it at another scholar.
--
-- ensure_scholar reports rather than raises. `orcid_conflict` in particular is a real
-- state (scholars_orcid_unique, #87: one iD, one scholar) and the two alternatives to
-- reporting it — failing the sign-in, or creating a row with a blank iD — are both
-- worse than saying so and letting a person decide.
--------------------------------------
create or replace function public.scholar_identity (_meta jsonb) returns table (orcid text, name text) language sql immutable
set
	search_path to '' as $$
  select
    coalesce(
      _meta->>'orcid',
      _meta->>'provider_id',
      _meta->>'sub'
    ),
    -- ORCID sends given_name/family_name and no `name`. Prefer `name` for providers that do
    -- send it; fall back to the composed form. Left null when the provider sends neither,
    -- so the scholar can supply one rather than being given a placeholder.
    coalesce(
      nullif(btrim(_meta->>'name'), ''),
      nullif(btrim(concat_ws(' ',
        _meta->>'given_name',
        _meta->>'family_name'
      )), '')
    );
$$;

alter function public.scholar_identity (jsonb) owner to postgres;

-- Called only from the SECURITY DEFINER functions below, which run as postgres.
revoke
execute on function public.scholar_identity (jsonb)
from
	public,
	anon,
	authenticated;

create or replace function public.handle_new_scholar () returns trigger language plpgsql security definer
set
	search_path to '' as $$
declare
  _identity record;
begin
  select * into _identity from public.scholar_identity(new.raw_user_meta_data);
  insert into public.scholars (id, orcid, name)
  values (new.id, _identity.orcid, _identity.name);
  return new;
end;
$$;

create or replace function public.ensure_scholar () returns text language plpgsql security definer
set
	search_path to '' as $$
declare
  _uid uuid := (select auth.uid());
  _meta jsonb;
  _identity record;
begin
  if _uid is null then
    return 'no_account';
  end if;

  -- The overwhelmingly common case: nothing to do, and no write.
  if exists (select 1 from public.scholars where id = _uid) then
    return 'exists';
  end if;

  select raw_user_meta_data into _meta from auth.users where id = _uid;
  if not found then
    return 'no_account';
  end if;

  select * into _identity from public.scholar_identity(_meta);

  if _identity.orcid is not null
    and exists (select 1 from public.scholars where orcid = _identity.orcid) then
    return 'orcid_conflict';
  end if;

  insert into public.scholars (id, orcid, name)
  values (_uid, _identity.orcid, _identity.name)
  on conflict (id) do nothing;

  return 'created';
end;
$$;

alter function public.ensure_scholar () owner to postgres;

revoke
execute on function public.ensure_scholar ()
from
	public,
	anon;

grant
execute on function public.ensure_scholar () to authenticated;

-- The trigger this repairs around. Re-asserted rather than assumed: it lives on
-- auth.users, which is outside the schema set the drift guard compares (config.toml
-- exposes only public and graphql_public), so nothing in CI has ever checked that it
-- is still there. `create or replace trigger` is idempotent where it already exists.
create or replace trigger on_auth_user_created
after insert on auth.users for each row
execute procedure public.handle_new_scholar ();
