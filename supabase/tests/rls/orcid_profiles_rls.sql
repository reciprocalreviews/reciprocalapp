-- Who may read and write public.orcid_profiles.
--
-- The mirror is world-READABLE on purpose: every field in it is already published at
-- orcid.org under the scholar's own visibility setting, and the volunteers roster and the
-- assignment table both render rows for scholars the viewer has no relationship to.
--
-- It is world-UNWRITABLE on purpose too, and that is the half worth testing. The section's
-- entire value is that it says what ORCID says; a scholar who could edit their own
-- affiliation would turn it into a claim RR was vouching for. There is no INSERT, UPDATE or
-- DELETE policy at all, so every write below fails -- and it must fail for the scholar's
-- OWN row as much as anyone else's, which is the case a policy written from habit would
-- have let through.

\ir ../_helpers/helpers.sql.inc

begin;

create extension if not exists pgtap
with
	schema extensions;

select
	plan (12);

select
	tests.create_scholar ('orcid_self@test.local') as self \gset

select
	tests.create_scholar ('orcid_other@test.local') as other \gset

select
	tests.create_scholar ('orcid_steward@test.local', true) as steward \gset

-- Seeded as the owner, which is the only way rows ever appear: the writer is the `orcid`
-- edge function running as service_role.
insert into
	public.orcid_profiles (scholar, orcid, employment_organization, keywords, work_count, fetch_status)
values
	(:'self', '0000-0001-2345-6789', 'University of Test', array['testing'], 12, 'ok');

-- ---- Reading -------------------------------------------------------------------
select
	tests.authenticate_as_anon ();

select
	is (
		(select employment_organization from public.orcid_profiles where scholar = :'self'),
		'University of Test',
		'anon can read a profile'
	);

select
	tests.authenticate_as (:'other');

select
	is (
		(select work_count from public.orcid_profiles where scholar = :'self'),
		12,
		'another scholar can read a profile'
	);

-- ---- Writing -------------------------------------------------------------------
-- A missing policy surfaces as 42501, the same as a missing column privilege: the
-- table-wide grants were revoked from anon and authenticated, so the statement is
-- rejected before RLS filtering would even apply.
select
	tests.authenticate_as (:'self');

select
	throws_ok (
		$$ update public.orcid_profiles set employment_organization = 'Somewhere Grander' where scholar = $$ || quote_literal(:'self'),
		'42501',
		null,
		'a scholar cannot edit their OWN mirrored affiliation'
	);

select
	throws_ok (
		$$ update public.orcid_profiles set keywords = array['whatever i like'] where scholar = $$ || quote_literal(:'self'),
		'42501',
		null,
		'a scholar cannot edit their own mirrored keywords'
	);

select
	throws_ok (
		$$ insert into public.orcid_profiles (scholar, orcid) values ($$ || quote_literal(:'other') || $$, '0000-0001-2345-6789') $$,
		'42501',
		null,
		'a scholar cannot insert a profile'
	);

select
	throws_ok (
		$$ delete from public.orcid_profiles where scholar = $$ || quote_literal(:'self'),
		'42501',
		null,
		'a scholar cannot delete their own profile'
	);

-- A steward administers RR; they do not get to rewrite what ORCID says either.
select
	tests.authenticate_as (:'steward');

select
	throws_ok (
		$$ update public.orcid_profiles set work_count = 9999 where scholar = $$ || quote_literal(:'self'),
		'42501',
		null,
		'not even a steward can edit the mirror'
	);

select
	tests.authenticate_as_anon ();

select
	throws_ok (
		$$ insert into public.orcid_profiles (scholar, orcid) values ($$ || quote_literal(:'other') || $$, '0000-0001-2345-6789') $$,
		'42501',
		null,
		'anon cannot insert a profile'
	);

-- ---- Column privileges ---------------------------------------------------------
-- Every column here is already public at orcid.org, with one exception. `fetch_detail`
-- carries OUR diagnostics -- HTTP statuses, parse errors, whether an API token was refused
-- -- and its comment always said it was never rendered to a visitor. But the grant used to
-- be table-wide, and not-rendered is not the same as not-readable: PostgREST hands out
-- whatever is granted, so anyone could read it with one request.
select
	tests.authenticate_as (:'other');

select
	lives_ok (
		$$ select employment_organization, keywords, work_count, fetch_status, fetch_rate_limited_at from public.orcid_profiles $$,
		'a client can read every public column, including the rate-limit stamp'
	);

select
	throws_ok (
		$$ select fetch_detail from public.orcid_profiles $$,
		'42501',
		null,
		'a client cannot read fetch_detail'
	);

-- The one that actually bites in practice: application code reaching for `*`. This is why
-- getORCIDProfile names its columns.
select
	throws_ok (
		$$ select * from public.orcid_profiles $$,
		'42501',
		null,
		'a wildcard select is refused, because it reaches fetch_detail'
	);

-- ---- The row dies with the account ---------------------------------------------
-- Distinct from erasure, which is an UPDATE that anonymises in place and therefore fires
-- no cascade at all -- see invariants/erasure.sql for that half.
select
	tests.clear_authentication ();

delete from auth.users
where
	id = :'self';

select
	is (
		(select count(*)::integer from public.orcid_profiles where scholar = :'self'),
		0,
		'deleting the auth user cascades the profile away'
	);

select
	*
from
	finish ();

rollback;
