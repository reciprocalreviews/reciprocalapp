-- Align ensure_scholar's body with the schema file that documents it.
--
-- 20260901000000_ensure_scholar.sql created the function with a shorter body: the
-- comment explaining why an ORCID collision is REPORTED rather than resolved lives in
-- supabase/schemas/scholars.sql and never made it into the migration. Postgres stores a
-- function's source verbatim, comments included, so `supabase db diff` sees two
-- different functions and CI's drift check fails — which is exactly what it is for, and
-- what 20260829030000_align_function_comments.sql was written for before it.
--
-- A NEW migration rather than an edit to that one. The original has already been applied
-- to staging; editing it in place would make CI green while leaving the hosted databases
-- holding the old body forever, which is the drift the check exists to catch, hidden
-- instead of fixed.
--
-- Behavior is identical. This changes only the text Postgres has on file.
--------------------------------------
create or replace function public.ensure_scholar () returns text language "plpgsql" security definer
set
	"search_path" to '' as $$
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

  -- scholars_orcid_unique: one iD identifies exactly one scholar (#87). If another row
  -- already holds this one, two accounts are claiming one researcher — reported rather
  -- than papered over, because the alternatives (fail the sign-in, or create a row with
  -- a blank iD) are both worse than saying so and letting a person decide.
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
