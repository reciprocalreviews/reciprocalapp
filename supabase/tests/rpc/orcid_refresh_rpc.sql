-- Claiming scholars for an ORCID refresh.
--
-- The claim, not the fetch, is what this file is about. private.claim_orcid_refresh stamps
-- fetch_attempted_at BEFORE asking the edge function for anything, and that ordering is
-- the only thing standing between "ten editors opened the same roster" and ten times the
-- ORCID traffic. A cooldown checked after the fetch would be decoration.
--
-- No network is involved. The secret_key and supabase_url vault secrets are unset in the
-- test database, so the function claims, warns that it cannot post, and returns -- which
-- is also the production behaviour when the function is not deployed yet, and is why the
-- rows stay claimed rather than being lost.

\ir ../_helpers/helpers.sql.inc

begin;

create extension if not exists pgtap
with
	schema extensions;

select
	plan (16);

select
	private.orcid_batch_size () as batch \gset

select
	tests.create_scholar ('orcid_rpc_a@test.local') as a \gset

select
	tests.create_scholar ('orcid_rpc_b@test.local') as b \gset

select
	tests.create_scholar ('orcid_rpc_none@test.local') as noid \gset

select
	tests.create_scholar ('orcid_rpc_steward@test.local', true) as steward \gset

-- Set as the owner: `orcid` is revoked from authenticated precisely so a scholar cannot
-- claim another researcher's identity.
update public.scholars
set
	orcid = '0000-0001-1111-1111'
where
	id = :'a';

update public.scholars
set
	orcid = '0000-0001-2222-2222'
where
	id = :'b';

-- :noid keeps a null orcid: an erased tombstone or a seeded fixture looks like this.
update public.scholars
set
	orcid = null
where
	id = :'noid';

-- ---- Authentication ------------------------------------------------------------
select
	tests.clear_authentication ();

select
	throws_ok (
		$$ select public.request_orcid_refresh(array[]::uuid[]) $$,
		null,
		'Authentication required',
		'an unauthenticated caller cannot request a refresh'
	);

-- ---- Claiming ------------------------------------------------------------------
select
	tests.authenticate_as (:'a');

select
	is (
		public.request_orcid_refresh (array[:'a'::uuid]),
		1,
		'a scholar with an iD and no profile is claimed'
	);

select
	is (
		(select fetch_status from public.orcid_profiles where scholar = :'a'),
		'pending',
		'the claimed row is pending until the fetch answers'
	);

select
	ok (
		(select fetch_attempted_at from public.orcid_profiles where scholar = :'a') > now() - interval '1 minute',
		'the claim stamps fetch_attempted_at before any fetch could have happened'
	);

select
	ok (
		(select fetched_at is null from public.orcid_profiles where scholar = :'a'),
		'fetched_at stays null: nothing has actually been read yet'
	);

-- ---- The cooldown --------------------------------------------------------------
select
	is (
		public.request_orcid_refresh (array[:'a'::uuid]),
		0,
		'a second immediate request claims nothing'
	);

select
	is (
		public.request_orcid_refresh (array[:'a'::uuid], true),
		0,
		'_force bypasses staleness but NOT the cooldown'
	);

-- Backdate past the cooldown to prove _force is doing something at all. As the owner:
-- `authenticated` has no UPDATE on this table at all, which orcid_profiles_rls.sql is the
-- file that proves.
select
	tests.clear_authentication ();

update public.orcid_profiles
set
	fetch_attempted_at = now() - interval '7 hours',
	fetched_at = now(),
	works_fetched_at = now(),
	fetch_status = 'ok'
where
	scholar = :'a';

select
	tests.authenticate_as (:'a');

select
	is (
		public.request_orcid_refresh (array[:'a'::uuid]),
		0,
		'a freshly fetched profile out of cooldown is still not stale'
	);

select
	is (
		public.request_orcid_refresh (array[:'a'::uuid], true),
		1,
		'_force re-claims a fresh profile once the cooldown has passed'
	);

-- ---- Who is skipped ------------------------------------------------------------
select
	is (
		public.request_orcid_refresh (array[:'noid'::uuid]),
		0,
		'a scholar with no ORCID iD is skipped, not failed'
	);

-- ---- Clamping ------------------------------------------------------------------
-- Passing every scholar id in the database must not become an unbounded fan-out.
select
	ok (
		public.request_orcid_refresh ((select array_agg(id) from public.scholars)) <= :batch,
		'a request is clamped to one batch however many ids it names'
	);

-- ---- Backfill ------------------------------------------------------------------
select
	tests.authenticate_as (:'b');

select
	throws_ok (
		$$ select public.backfill_orcid_profiles(10) $$,
		'RR006',
		null,
		'a scholar who is not a steward cannot backfill'
	);

-- A scholar the clamp test above cannot have swept up, so this asserts what backfill does
-- rather than what the preceding test left behind: everything else with an iD is inside
-- its cooldown by now, and a backfill finding nothing would be correct but would prove
-- nothing.
select
	tests.clear_authentication ();

select
	tests.create_scholar ('orcid_rpc_cold@test.local') as cold \gset

update public.scholars
set
	orcid = '0000-0001-3333-3333'
where
	id = :'cold';

select
	tests.authenticate_as (:'steward');

select
	is (
		public.backfill_orcid_profiles (5),
		1,
		'a steward can backfill a profile that has never been fetched'
	);

-- ---- Mirror health --------------------------------------------------------------
-- The counts a steward reads to decide whether the mirror needs attention. `failed` alone
-- cannot answer that: it counts 500s and timeouts as well as 429s, and only the 429 says
-- "we are exhausting ORCID's anonymous budget and should register an API client" (#173).
select
	tests.authenticate_as (:'b');

select
	throws_ok (
		$$ select public.orcid_mirror_health() $$,
		'RR006',
		null,
		'a scholar who is not a steward cannot read mirror health'
	);

select
	tests.clear_authentication ();

update public.orcid_profiles
set
	fetch_status = 'error',
	fetch_rate_limited_at = now()
where
	scholar = :'a';

select
	tests.authenticate_as (:'steward');

select
	is (
		(public.orcid_mirror_health () ->> 'rate_limited')::integer,
		1,
		'a recent 429 is counted'
	);

select
	tests.clear_authentication ();

-- Windowed, not lifetime: a burst six months ago is history, and a steward needs to know
-- about pressure now.
update public.orcid_profiles
set
	fetch_rate_limited_at = now() - interval '30 days'
where
	scholar = :'a';

select
	tests.authenticate_as (:'steward');

select
	is (
		(public.orcid_mirror_health () ->> 'rate_limited')::integer,
		0,
		'a rate limit from a month ago is not counted'
	);

select
	*
from
	finish ();

rollback;
