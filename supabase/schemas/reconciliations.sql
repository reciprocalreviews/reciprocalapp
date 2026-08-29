-- Daily reconciliation of the token economy against its own records.
--
-- The backup work established that assertions are what catch real problems:
-- three separate defects survived every piece of reasoning about the restore and
-- were found only by checking. This is the same idea applied continuously to live
-- data, so corruption is found the morning after rather than whenever someone
-- happens to notice a balance looks wrong.
--
-- Each check answers a question nothing else in the schema can:
--
--   1. unattributed_moves   — did value move without a transaction explaining it?
--   2. replay_mismatches    — does the ledger still reproduce current state?
--   3. chain_breaks         — did a write escape the logging trigger?
--   4. placeholders         — is an approved transaction still holding null-UUIDs?
--   5. dangling_token_refs  — does an approved transaction cite a token that is
--                             gone, or in another currency?
--   6. conservation         — do the two narratives agree, holder by holder?
--   7. orphan_proposals     — did a multi-step client write leave half a record?
--------------------------------------
-- Where results are kept. Append-only by convention rather than by trigger: this
-- is a monitoring record, not evidence, and a stuck row should be correctable.
create table if not exists public.reconciliations (
	id uuid primary key default gen_random_uuid(),
	ran_at timestamptz not null default now(),
	ok boolean not null,
	result jsonb not null,
	-- How long the run took. Recorded because the failure mode of this job is not
	-- a wrong answer but no answer: three of its checks scan the whole history of
	-- the token ledger, which only grows, and a cron job that starts timing out
	-- stops reporting silently. A visible trend is the warning.
	duration_ms integer
);

alter table public.reconciliations OWNER to "postgres";

create index reconciliations_ran_at_index on public.reconciliations using btree (ran_at desc);

-- Nobody reads this through the API. It describes the integrity of the whole
-- economy, which is not a scholar's business.
alter table public.reconciliations ENABLE row LEVEL SECURITY;

revoke all on table public.reconciliations
from
	anon,
	authenticated;

-- Explicitly revoked, not merely un-granted: Supabase's default privileges give
-- service_role ALL on every new table in `public` before this file's grant runs,
-- so `grant select` alone left INSERT, UPDATE and DELETE in place and the line
-- below described a restriction that did not exist.
revoke insert,
update,
delete on table public.reconciliations
from
	service_role;

grant
select
	on table public.reconciliations to service_role;

--------------------------------------
-- _since bounds the three checks that scan the ENTIRE token history -- replay,
-- chain and dangling refs -- to events and transactions at or after that moment.
-- Null means everything, which is what a deliberate investigation wants; the
-- nightly cron passes a window, because those three grow without bound while the
-- rest do not.
--
-- Conservation (check 6) is deliberately NOT bounded. It compares current state
-- against the transactions that produced it, so it is O(the economy) rather than
-- O(its history) -- it does not grow with time, and it is the check that catches
-- a lost or duplicated payment. Narrowing it to save time would give away the
-- one invariant most worth having.
create or replace function public.reconcile_ledger (_since timestamptz default null) returns jsonb language plpgsql security definer
set
	search_path='' as $$
declare
	_started timestamptz := clock_timestamp();
	_duration integer;
	_unattributed int;
	_unattributed_mints int;
	_replay int;
	_chain int;
	_placeholder int;
	_dangling int;
	_conservation jsonb;
	_conservation_n int := 0;
	_orphans int;
	_result jsonb;
	_ok boolean;
begin
	-- 1. Value that MOVED with no transaction explaining it. The single most
	-- important number here: in a healthy system it is zero, and anything else is
	-- an application bug, a migration that touched tokens directly, or someone with
	-- privileged access moving balances by hand.
	select count(*) into _unattributed
	from public.token_events
	where op = 'move' and txn is null;

	-- Tokens CREATED with no transaction explaining them. In production this is
	-- counterfeiting and should be zero. It is reported rather than failing the
	-- run, because supabase/seed.sql inserts tokens directly — every development
	-- and CI database legitimately has hundreds of these, and a check that is
	-- always red is a check nobody reads.
	select count(*) into _unattributed_mints
	from public.token_events
	where op = 'mint' and txn is null;

	-- 2. Does replaying the log still reproduce the tokens table exactly? If this
	-- drifts, either a write escaped the trigger or the log has been tampered with.
	-- Bounded by _since to the tokens that actually MOVED in the window. Replaying
	-- the whole log means a distinct-on over every event ever recorded, which is
	-- the single most expensive thing this function does; restricting it to
	-- recently-moved tokens asks the question that matters ("did anything that
	-- moved lately end up inconsistent?") at a cost that does not grow with age.
	select count(*) into _replay
	from public.tokens t
	full outer join public.tokens_as_of() a on a.token = t.id
	where (
			_since is null
			or coalesce(t.id, a.token) in (
				select e.token from public.token_events e where e.at >= _since
			)
		)
		and (
			t.id is null
			or a.token is null
			or (t.scholar, t.venue, t.currency) is distinct from (a.scholar, a.venue, a.currency)
		);

	-- 3. Each event's "previous owner" must match the prior event for that token.
	-- A break means a change happened that the trigger did not see — which a plain
	-- state comparison cannot detect, because the end state may still look right.
	-- Bounded the same way. The window function still needs each token's events in
	-- order, so the filter is on the TOKEN having moved in the window rather than
	-- on the individual event -- otherwise the first event inside the window would
	-- lose the predecessor it has to be compared against.
	select count(*) into _chain
	from (
		select
			e.prev_scholar, e.prev_venue,
			lag(e.scholar) over w as prior_scholar,
			lag(e.venue) over w as prior_venue,
			lag(e.seq) over w as prior_seq
		from public.token_events e
		where _since is null
			or e.token in (select e2.token from public.token_events e2 where e2.at >= _since)
		window w as (partition by e.token order by e.seq)
	) s
	where prior_seq is not null
		and (prev_scholar, prev_venue) is distinct from (prior_scholar, prior_venue);

	-- 4. An approved transaction still carrying placeholder UUIDs never had its
	-- tokens assigned — the amount is recorded but the movement is fiction.
	select count(*) into _placeholder
	from public.transactions
	where status = 'approved'
		and (
			'00000000-0000-0000-0000-000000000000'::uuid = any (tokens)
			or cardinality(tokens) = 0
		);

	-- 5. Every token an approved transaction cites must exist, in that currency.
	-- Bounded by transaction age. Unnesting every approved transaction's token
	-- array materializes one row per token ever moved, so this is the check whose
	-- cost is literally the platform's lifetime volume.
	select count(*) into _dangling
	from public.transactions x
	cross join lateral unnest(x.tokens) as tok(id)
	left join public.tokens t on t.id = tok.id
	where x.status = 'approved'
		and (_since is null or x.created_at >= _since)
		and tok.id <> '00000000-0000-0000-0000-000000000000'::uuid
		and (t.id is null or t.currency <> x.currency);

	-- 6. Conservation: for each holder and currency, the balance implied by
	-- approved transactions must equal the tokens actually held.
	--
	-- Only meaningful once every movement is attributed. Tokens written directly —
	-- as supabase/seed.sql does, and as any hand-repair would — exist with no
	-- transaction to account for them, so this would report drift that check 1 has
	-- already explained. Skipped rather than reported as a false violation.
	if _unattributed = 0 and _unattributed_mints = 0 then
		with moved as (
			select to_venue as holder, 'venue' as kind, currency, sum(cardinality(tokens)) as n
				from public.transactions where status = 'approved' and to_venue is not null group by 1, 3
			union all
			select from_venue, 'venue', currency, -sum(cardinality(tokens))
				from public.transactions where status = 'approved' and from_venue is not null group by 1, 3
			union all
			select to_scholar, 'scholar', currency, sum(cardinality(tokens))
				from public.transactions where status = 'approved' and to_scholar is not null group by 1, 3
			union all
			select from_scholar, 'scholar', currency, -sum(cardinality(tokens))
				from public.transactions where status = 'approved' and from_scholar is not null group by 1, 3
		),
		expected as (select holder, kind, currency, sum(n) as expected from moved group by 1, 2, 3),
		actual as (
			select venue as holder, 'venue' as kind, currency, count(*) as actual
				from public.tokens where venue is not null group by 1, 3
			union all
			select scholar, 'scholar', currency, count(*)
				from public.tokens where scholar is not null group by 1, 3
		)
		select coalesce(jsonb_agg(jsonb_build_object(
			'kind', coalesce(e.kind, a.kind),
			'holder', coalesce(e.holder, a.holder),
			'currency', coalesce(e.currency, a.currency),
			'expected', coalesce(e.expected, 0),
			'actual', coalesce(a.actual, 0)
		)), '[]'::jsonb), count(*)
		into _conservation, _conservation_n
		from expected e
		full outer join actual a
			on a.holder = e.holder and a.kind = e.kind and a.currency = e.currency
		where coalesce(e.expected, 0) <> coalesce(a.actual, 0);
	else
		_conservation := to_jsonb('skipped: unattributed token provenance present'::text);
	end if;

	-- 7. A proposal with no supporters is the signature of proposeVenue crashing
	-- between its two client-side writes — the proposal exists and the record of
	-- who proposed it does not.
	select count(*) into _orphans
	from public.proposals p
	where not exists (select 1 from public.supporters s where s.proposalid = p.id);

	-- `ok` covers only what must hold in EVERY environment. The advisory block
	-- below is real signal in production but expected to be non-zero anywhere
	-- seeded by supabase/seed.sql, and folding it into `ok` would make local and CI
	-- runs permanently red — which is how a monitoring check becomes wallpaper.
	_ok := _unattributed = 0
		and _replay = 0
		and _chain = 0
		and _placeholder = 0
		and _dangling = 0
		and _conservation_n = 0;

	_result := jsonb_build_object(
		'ok', _ok,
		'invariants', jsonb_build_object(
			'unattributed_moves', _unattributed,
			'replay_mismatches', _replay,
			'chain_breaks', _chain,
			'placeholders_in_approved', _placeholder,
			'dangling_token_refs', _dangling,
			'conservation_violations', _conservation
		),
		-- Watch these on production, where both should be zero.
		'advisory', jsonb_build_object(
			'unattributed_mints', _unattributed_mints,
			'orphan_proposals', _orphans
		)
	);

	_duration := (extract(epoch from clock_timestamp() - _started) * 1000)::integer;
	_result := jsonb_set(_result, '{window}', case when _since is null
		then to_jsonb('all history'::text) else to_jsonb(_since) end);
	_result := jsonb_set(_result, '{duration_ms}', to_jsonb(_duration));

	insert into public.reconciliations (ok, result, duration_ms) values (_ok, _result, _duration);

	-- A check nobody is told about is wallpaper. On failure this goes three ways:
	-- the reconciliations table for history, the Postgres log for anyone looking at
	-- the project, and email to the stewards so it reaches a person.
	--
	-- Inserted directly rather than through queue_email: that RPC resolves
	-- recipients from a caller's scholar ids and is built for the authenticated
	-- request path, whereas this runs from pg_cron with no caller at all. The
	-- INSERT is available here because this function is SECURITY DEFINER and owned
	-- by postgres; the revoke that closed the open-relay hole applies to
	-- authenticated and anon.
	--
	-- One row to the shared steward inbox rather than one per steward. The old
	-- per-steward fan-out required a VERIFIED contact address, which meant the
	-- check that reports the ledger is broken could itself reach nobody — the
	-- worst possible thing to be conditional. The alias always resolves.
	if not _ok then
		raise warning 'reconcile_ledger found violations: %', _result;

		insert into public.emails (event, email, scholar, args)
		values (
			'ReconciliationFailed',
			public.steward_inbox(),
			null,
			jsonb_build_array(
				to_char(now() at time zone 'utc', 'YYYY-MM-DD HH24:MI') || ' UTC',
				-- A compact summary rather than raw JSON: the recipient needs to know
				-- which checks failed and how badly, not to parse a payload.
				concat_ws(', ',
					nullif('unattributed moves: ' || _unattributed, 'unattributed moves: 0'),
					nullif('replay mismatches: ' || _replay, 'replay mismatches: 0'),
					nullif('chain breaks: ' || _chain, 'chain breaks: 0'),
					nullif('approved transactions holding placeholders: ' || _placeholder, 'approved transactions holding placeholders: 0'),
					nullif('dangling token references: ' || _dangling, 'dangling token references: 0'),
					nullif('conservation violations: ' || _conservation_n, 'conservation violations: 0')
				)
			)
		);
	end if;

	return _result;
end;
$$;

alter function public.reconcile_ledger (timestamptz) OWNER to "postgres";

revoke
execute on function public.reconcile_ledger (timestamptz)
from
	public,
	anon,
	authenticated;

grant
execute on function public.reconcile_ledger (timestamptz) to service_role;

--------------------------------------
-- Scheduling lives in the migration, not here: cron.job is cluster state rather
-- than schema, captured separately by supabase/dr/dump.sh and restored from
-- quarantine's record. See migrations 20260808010000 and 20260830030000.
--
-- Two schedules: a bounded run nightly at 22:15, which is the alarm, and an
-- unbounded one weekly, which closes the hole bounding opens -- the window keys
-- on a token having moved recently, and a write that escaped the logging trigger
-- leaves no event to move it into view.
