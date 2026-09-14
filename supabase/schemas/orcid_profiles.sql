--------------------------------------
-- ORCID profile mirror
--
-- A cache of the narrow, review-relevant slice of a scholar's PUBLIC ORCID record, so an
-- editor choosing a reviewer can see who someone is without opening orcid.org in another
-- tab. See DESIGN.md's Scholar route section for what is mirrored and what deliberately
-- is not, and ARCHITECTURE.md's "ORCID profile mirror" for how it is filled.
--
-- Three properties are worth stating up front, because the rest of this file follows from
-- them:
--
--   1. It is DERIVED. Every row can be rebuilt by re-fetching, which is why it is not
--      audited, not in the realtime publication, and hard-deleted rather than scrubbed on
--      erasure.
--   2. It is already PUBLIC. The ORCID public API returns only items the scholar set to
--      public visibility, so ORCID's own privacy setting is the consent mechanism and
--      there is no RR-side toggle to explain.
--   3. Nobody may WRITE it, not even about themselves. The section's whole value is that
--      it says what ORCID says; a writable mirror would be a claim RR was vouching for.
create table if not exists public.orcid_profiles (
	-- Keyed on the scholar rather than the iD, so PostgREST can embed it from any
	-- query that already has scholars in it.
	scholar uuid not null,
	-- The iD this cache was fetched FOR. Deliberately not derived at read time from
	-- scholars.orcid: erasure nulls that column, so a row whose contents came from an
	-- iD the scholar no longer holds has to be detectable rather than silently
	-- re-attributed to whoever holds the row now.
	orcid text not null,
	-- Current affiliation. Three columns rather than one rendered string, because the
	-- roster and the assignment table show different subsets of it -- the table drops
	-- the department, which is the least discriminating part and the narrowest cell --
	-- and joining them in SQL would take that choice away.
	employment_role text,
	employment_department text,
	employment_organization text,
	-- Most recent education, as a seniority signal: a first-year PhD student and a
	-- senior researcher carry very different reviewing-load norms.
	education_role text,
	education_organization text,
	education_year smallint,
	-- Self-declared topics. An array rather than child rows because the volunteers
	-- roster does all of its keyword work in JavaScript over rows already in memory,
	-- so child rows would add an embed and buy no capability. A GIN index makes this
	-- server-side filterable later without restructuring.
	keywords text[] not null default '{}',
	-- The few most recent works: [{ title, year, journal, doi, url }]. jsonb rather
	-- than child rows because it is bounded, display-only, and never filtered or
	-- aggregated in SQL -- the aggregates below are computed over the FULL set, which
	-- child rows holding only these could not produce.
	works jsonb not null default '[]',
	-- Counted over every work in the record. Nullable, and null is NOT 0: null means
	-- the works section has not been read, 0 means it was read and is empty. The
	-- interface branches on the difference.
	work_count integer,
	work_first_year smallint,
	work_last_year smallint,
	-- Researcher urls and external identifiers: [{ kind, label, value, url }].
	links jsonb not null default '[]',
	-- Two clocks, because /works is the only expensive fetch: 787KB uncompressed for a
	-- prolific record against 8.3KB for the other three sections combined.
	fetched_at timestamptz,
	works_fetched_at timestamptz,
	-- The claim stamp, written BEFORE the fetch is asked for. That ordering is the
	-- whole reason the cooldown is a stampede guard rather than a hope: ten editors
	-- opening the same roster claim once between them, not ten times.
	fetch_attempted_at timestamptz not null default now(),
	fetch_status text not null default 'pending',
	-- Consecutive failures, for backoff. Reset to zero on success.
	fetch_failures smallint not null default 0,
	-- Diagnostics for whoever is looking at the row. Never rendered to a visitor, and --
	-- unlike every other column here -- never granted to one either: the SELECT grant below
	-- names its columns and leaves this one out, because "not rendered" and "not readable"
	-- are different things and PostgREST hands out whatever is granted. Same reason
	-- pending_email_verification omits delivery_detail.
	fetch_detail text,
	-- When ORCID last answered a read for this scholar with 429.
	--
	-- Its own column rather than something parsed back out of fetch_detail: 'error'
	-- conflates a 429 with a 500, a timeout and a parse failure, and only the 429 answers
	-- the question a steward is actually asking -- are we exhausting the anonymous daily
	-- budget, and should this project register an API client (#173). Null means never.
	fetch_rate_limited_at timestamptz
);

alter table public.orcid_profiles owner to "postgres";

alter table only public.orcid_profiles
add constraint orcid_profiles_pkey primary key (scholar);

alter table only public.orcid_profiles
add constraint orcid_profiles_scholar_fkey foreign key (scholar) references public.scholars (id) on delete cascade;

-- A four-value vocabulary, enforced rather than conventional, following
-- emails_delivery_status: the interface branches on these exact words.
--   pending   -- claimed, no answer yet
--   ok        -- fetched and parsed
--   not_found -- ORCID answered 404/409: no such record, or deactivated
--   error     -- 5xx, 429, timeout, or unparseable
alter table only public.orcid_profiles
add constraint orcid_profiles_fetch_status check (
	fetch_status in ('pending', 'ok', 'not_found', 'error')
);

-- Bounded here rather than trusted from the writer. The writer is a separately deployed
-- edge function, which can go stale against this schema between deploys.
alter table only public.orcid_profiles
add constraint orcid_profiles_works_bounded check (jsonb_array_length(works)<=5);

-- Both payload columns are arrays. Without this a scalar or object would satisfy the
-- column type and break every reader that iterates them.
alter table only public.orcid_profiles
add constraint orcid_profiles_shapes check (
	jsonb_typeof(works)='array'
	and jsonb_typeof(links)='array'
);

-- The claim query's driving scan: "who is stale and out of cooldown".
create index if not exists orcid_profiles_attempted_index on public.orcid_profiles using btree (fetch_attempted_at);

--------------------------------------
-- Security
--
alter table public.orcid_profiles enable row level security;

-- Explicitly revoked, not merely un-granted: Supabase's default privileges hand anon and
-- authenticated ALL on every new table in `public` before this line runs. The same
-- correction token_events and erasures make.
revoke all on table public.orcid_profiles
from
	anon,
	authenticated;

-- Columns, not the whole table. Everything here is already public at orcid.org with one
-- exception: fetch_detail carries our own diagnostics -- HTTP statuses, parse errors, and
-- whether an API token was refused -- which are nobody else's business and would otherwise
-- be readable by anyone over PostgREST.
grant
select
	(
		scholar,
		orcid,
		employment_role,
		employment_department,
		employment_organization,
		education_role,
		education_organization,
		education_year,
		keywords,
		works,
		work_count,
		work_first_year,
		work_last_year,
		links,
		fetched_at,
		works_fetched_at,
		fetch_attempted_at,
		fetch_status,
		fetch_failures,
		fetch_rate_limited_at
	) on table public.orcid_profiles to anon,
	authenticated;

grant all on table public.orcid_profiles to service_role;

-- World-readable, exactly as scholars is, and for a stronger reason: every field here is
-- already published at orcid.org under the scholar's own visibility setting, so withholding
-- it would protect nothing while making the mirror disagree with its source. It is also
-- what makes the volunteers roster and the assignment table possible at all -- both render
-- rows for scholars the viewer has no relationship to.
create policy "ORCID profiles are public" on public.orcid_profiles for
select
	to authenticated,
	anon using (true);

-- No INSERT, UPDATE or DELETE policy, deliberately. The only writer is the `orcid` edge
-- function running as service_role, which bypasses RLS. A scholar cannot edit this for the
-- same reason they cannot edit scholars.orcid.
--------------------------------------
-- Refreshing
--
-- The shape here is the one send_email() established: a database-side event fires a
-- best-effort net.http_post at an edge function carrying the secret_key on the `apikey`
-- header, records that it was asked for, and never rolls back the caller. Delivery is a
-- deployment concern and must not be able to fail a page load or a sign-in.
--
-- Staleness lives HERE and nowhere else. TypeScript never computes it; the interface only
-- reads fetched_at to render an "as of" date. One source of truth for how old is too old.
-- How many scholars travel in one post to the edge function. The function fetches three
-- to four ORCID endpoints per scholar, and the anonymous public API allows 12 requests a
-- second, so a batch of twenty is a few seconds of work for it.
create or replace function private.orcid_batch_size () returns integer language sql immutable
set
	search_path='' as $$ select 20 $$;

alter function private.orcid_batch_size () owner to "postgres";

/**
 * Claim a set of scholars for refresh and ask the edge function to fetch them.
 *
 * Returns how many were claimed. Claiming is what makes the cooldown work: the stamp is
 * written before the fetch is requested, so concurrent readers of the same roster produce
 * one fetch per scholar per cooldown rather than one per reader.
 *
 * `_force` bypasses the staleness clocks but NOT the cooldown, so no caller -- not a
 * sign-in, not a backfill, not a button -- can turn this into a flood of ORCID traffic.
 */
create or replace function private.claim_orcid_refresh (_ids uuid[], _force boolean default false) returns integer language plpgsql security definer
set
	search_path='' as $$
declare
	-- btrim so a secret pasted with a stray newline still works.
	_key text := btrim(coalesce(private.get_secret('secret_key'), ''));
	_url text := btrim(coalesce(private.get_secret('supabase_url'), ''));
	_claimed uuid[];
	_batch jsonb;
	_size integer := private.orcid_batch_size();
	_offset integer := 0;
begin
	if _ids is null or cardinality(_ids) = 0 then return 0; end if;

	-- Claim. A scholar with no iD is skipped rather than failed: that is an erased
	-- tombstone or a seeded fixture, and there is nothing to fetch for either. This is
	-- also the first of the two guards that stop a batch claimed just before an erasure
	-- from writing the row back after it -- the second is in the edge function, which
	-- re-reads scholars.orcid at write time.
	with candidates as (
		select s.id, s.orcid
		from public.scholars s
		left join public.orcid_profiles p on p.scholar = s.id
		where s.id = any (_ids)
			and s.orcid is not null
			-- Out of cooldown. Coalesced to -infinity so a row that has never been
			-- attempted is always eligible.
			and coalesce(p.fetch_attempted_at, '-infinity'::timestamptz) < now() - interval '6 hours'
			and (
				_force
				or p.scholar is null
				-- The profile sections, on a 30 day clock.
				or p.fetched_at is null
				or p.fetched_at < now() - interval '30 days'
				-- Works, on a 90 day clock of their own: they are the expensive fetch.
				or p.works_fetched_at is null
				or p.works_fetched_at < now() - interval '90 days'
			)
	), claimed as (
		insert into public.orcid_profiles as p (scholar, orcid, fetch_attempted_at, fetch_status)
		select c.id, c.orcid, now(), 'pending' from candidates c
		on conflict (scholar) do update set
			fetch_attempted_at = now(),
			-- Follow a scholar whose iD changed, so the row cannot keep serving contents
			-- fetched for somebody else's record.
			orcid = excluded.orcid
		returning p.scholar
	)
	select array_agg(scholar) into _claimed from claimed;

	if _claimed is null or cardinality(_claimed) = 0 then return 0; end if;

	-- Nothing to post to. The rows stay claimed and terminally 'pending', which the next
	-- attempt after the cooldown will pick up again.
	if _key = '' or _url = '' then
		raise warning 'claim_orcid_refresh: % is not configured, so % profiles were claimed but not fetched',
			case when _url = '' then 'the supabase_url vault secret' else 'the secret_key vault secret' end,
			cardinality(_claimed);
		return cardinality(_claimed);
	end if;

	-- Post in batches. A backfill can claim far more than one batch, and the edge function
	-- paces itself within a batch but cannot pace across an unbounded one.
	while _offset < cardinality(_claimed) loop
		select jsonb_agg(
			jsonb_build_object(
				'scholar', p.scholar,
				'orcid', p.orcid,
				-- Per scholar, so the expensive section is asked for only when its own
				-- clock expired rather than on every profile refresh.
				'works', (p.works_fetched_at is null or p.works_fetched_at < now() - interval '90 days')
			)
		) into _batch
		from public.orcid_profiles p
		where p.scholar = any (_claimed[_offset + 1 : _offset + _size]);

		begin
			-- If the supabase URL is localhost, rewrite it so the container reaches the
			-- host machine. The key goes on `apikey`: Authorization: Bearer is reserved
			-- for JWTs and the opaque sb_secret_... keys are rejected there.
			perform net.http_post(
				url := replace(_url, '127.0.0.1', 'host.docker.internal') || '/functions/v1/orcid',
				headers := jsonb_build_object('Content-Type', 'application/json', 'apikey', _key)::jsonb,
				body := jsonb_build_object('scholars', _batch)
			);
		exception when others then
			-- pg_net validates the URL synchronously, so a malformed value raises here
			-- rather than in the background worker. Warn and carry on: the rows are
			-- claimed, and the next attempt after the cooldown will try again.
			raise warning 'claim_orcid_refresh: could not queue a batch: % (%)', sqlerrm, sqlstate;
		end;

		_offset := _offset + _size;
	end loop;

	return cardinality(_claimed);
end;
$$;

alter function private.claim_orcid_refresh (uuid[], boolean) owner to "postgres";

revoke
execute on function private.claim_orcid_refresh (uuid[], boolean)
from
	public,
	anon,
	authenticated;

/**
 * Refresh a handful of scholars, for a page that has just rendered them.
 *
 * Called without awaiting it, from the browser, after paint -- never from a `load`, which
 * would put ORCID's availability on the critical path of a page that has a dozen queries
 * already. Every surface renders whatever the cache holds right now, possibly nothing, and
 * this lands for the next reader.
 */
create or replace function public.request_orcid_refresh (_scholars uuid[], _force boolean default false) returns integer language plpgsql security definer
set
	search_path='' as $$
declare
	_ids uuid[];
begin
	if (select auth.uid()) is null then
		raise exception 'Authentication required';
	end if;
	if _scholars is null then return 0; end if;

	-- Clamped, and distinct, so one call cannot be turned into an unbounded fan-out by a
	-- caller that passes every scholar it can name.
	select array_agg(id) into _ids from (
		select distinct s as id from unnest(_scholars) s limit (select private.orcid_batch_size())
	) capped;

	return private.claim_orcid_refresh(_ids, _force);
end;
$$;

alter function public.request_orcid_refresh (uuid[], boolean) owner to "postgres";

revoke
execute on function public.request_orcid_refresh (uuid[], boolean)
from
	public,
	anon;

-- Ordinary RPC: authenticated only. Anonymous visitors deliberately do not warm the cache
-- -- an anon visitor to a cold profile sees the ORCID link and nothing else. The editors
-- this feature is for are always signed in, and leaving it out closes a crawler-driven
-- path into ORCID's daily budget.
grant
execute on function public.request_orcid_refresh (uuid[], boolean) to authenticated;

/**
 * Populate profiles that have never been fetched, oldest attempt first.
 *
 * The bootstrap. Without it every row is cold on the day this ships and stays cold until
 * its scholar signs in or somebody opens a page showing them -- so the editors the mirror
 * exists for would see an empty section for months.
 *
 * Steward-gated and re-runnable: the cooldown and the staleness clocks make a second run
 * claim only what the first did not, so it can be called repeatedly until it returns 0.
 * `_limit` is what paces it against ORCID's daily budget -- roughly four requests per
 * scholar, against 25k a day unauthenticated.
 */
create or replace function public.backfill_orcid_profiles (_limit integer default 100) returns integer language plpgsql security definer
set
	search_path='' as $$
declare
	_ids uuid[];
begin
	if not public.isSteward() then
		raise exception 'Only a steward can backfill ORCID profiles' using errcode = 'RR006';
	end if;

	-- Never-fetched rows first, then the longest-unattempted. That ordering is what makes
	-- a paced backfill converge: each run takes the oldest slice rather than re-walking
	-- the same head of the table.
	select array_agg(id) into _ids from (
		select s.id
		from public.scholars s
		left join public.orcid_profiles p on p.scholar = s.id
		where s.orcid is not null
			and (p.scholar is null or p.fetched_at is null or p.fetched_at < now() - interval '30 days')
			and coalesce(p.fetch_attempted_at, '-infinity'::timestamptz) < now() - interval '6 hours'
		order by p.fetched_at asc nulls first, p.fetch_attempted_at asc nulls first
		limit least(greatest(coalesce(_limit, 100), 1), 500)
	) due;

	return private.claim_orcid_refresh(_ids, false);
end;
$$;

alter function public.backfill_orcid_profiles (integer) owner to "postgres";

revoke
execute on function public.backfill_orcid_profiles (integer)
from
	public,
	anon;

-- Steward-gated rather than owner-only: a steward runs this from the SQL editor or a
-- script after a deploy, so it needs to be callable as a signed-in user. The isSteward()
-- check inside is the gate; the grant only decides who may reach it.
grant
execute on function public.backfill_orcid_profiles (integer) to authenticated;

/**
 * How the mirror is doing, for a steward deciding whether it needs attention.
 *
 * The counts exist because `fetch_status = 'error'` cannot answer the only operational
 * question there is: a 429 means we are exhausting ORCID's anonymous daily budget and should
 * register an API client (#173), while a 500 or a timeout means ORCID had a bad minute and
 * the backoff will handle it. They are different problems with different responses, and the
 * status column alone conflates them.
 *
 * Steward-gated to match the card that renders it, not because the numbers are secret --
 * `orcid_profiles` is world-readable and anyone could count these rows themselves. It is an
 * operational view, and it belongs where the other operational controls are.
 */
create or replace function public.orcid_mirror_health () returns jsonb language plpgsql security definer
set
	search_path='' as $$
declare
	_result jsonb;
begin
	if not public.isSteward() then
		raise exception 'Only a steward can read ORCID mirror health' using errcode = 'RR006';
	end if;

	select jsonb_build_object(
		-- The denominator: scholars who HAVE an iD, so an erased tombstone or a seeded
		-- fixture is not counted as a profile we are failing to read.
		'scholars', count(*) filter (where s.orcid is not null),
		'read', count(*) filter (where p.fetch_status = 'ok' and p.fetched_at is not null),
		'never_read', count(*) filter (where s.orcid is not null and p.scholar is null),
		'pending', count(*) filter (where p.fetch_status = 'pending'),
		'not_found', count(*) filter (where p.fetch_status = 'not_found'),
		'failed', count(*) filter (where p.fetch_status = 'error'),
		-- The number that decides whether to act. Windowed rather than lifetime: a burst
		-- six months ago is history, and a steward needs to know about pressure now.
		'rate_limited', count(*) filter (where p.fetch_rate_limited_at > now() - interval '7 days'),
		'oldest_read', min(p.fetched_at)
	) into _result
	from public.scholars s
	left join public.orcid_profiles p on p.scholar = s.id;

	return _result;
end;
$$;

alter function public.orcid_mirror_health () owner to "postgres";

revoke
execute on function public.orcid_mirror_health ()
from
	public,
	anon;

grant
execute on function public.orcid_mirror_health () to authenticated;
