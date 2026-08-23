-- Route steward notifications to one shared inbox instead of N private copies.
--
-- `ProposalCreatedStewards` and `ReconciliationFailed` each resolved every steward and
-- mailed them individually. That has three problems: no steward can see whether another
-- has already picked a request up, there is no thread to discuss it in, and a steward
-- with no verified contact address was silently skipped — so a reconciliation failure
-- could reach nobody at all.
--
-- stewards@reciprocal.reviews is a Google Group in collaborative-inbox mode: members
-- still receive the mail in their own inboxes, and additionally get a shared thread they
-- can assign and resolve. Sending only to the alias therefore loses nothing.

--------------------------------------
-- The alias, defined once.
--
-- Hardcoded rather than configured: it is a property of the deployment's DNS, changes
-- about never, and a settings table would make a silent misconfiguration possible in the
-- one path that reports that other paths are broken. Mirrored in
-- supabase/functions/_shared/emailShell.ts as SUPPORT_EMAIL — keep the two in sync.
create or replace function public.steward_inbox () returns text language sql immutable
set
	"search_path" to '' as $$
	select 'stewards@reciprocal.reviews'::text;
$$;

alter function public.steward_inbox () OWNER to "postgres";

grant execute on function public.steward_inbox () to authenticated;

--------------------------------------
-- queue_steward_email: queue a steward notification to the shared inbox.
--
-- Deliberately a separate function from queue_email rather than another branch inside it.
-- queue_email's security rests on never accepting a recipient: it resolves scholars by id
-- or reads a proposal's editors. This function accepts no recipient either — the address
-- is fixed — but it does bypass the "recipient must be a scholar with a verified email"
-- rule, so the safety has to come from somewhere else. It comes from the event whitelist:
-- without it, any authenticated user could render ANY template into the stewards' inbox,
-- which is precisely the mailbox least able to ignore what arrives.
--
-- The residual exposure is bounded and deliberate: an authenticated user can queue a
-- steward notification with argument values of their choosing. That is the same shape as
-- queue_email's residual (no prose, no links, attributable via emails.sender), and the
-- inbox is staffed by the people best placed to recognize junk.
create or replace function public.queue_steward_email (_event text, _args text[] default '{}') returns void language plpgsql security definer
set
	"search_path" to 'public', 'pg_temp' as $$
declare
	_caller uuid := (select auth.uid());
begin
	if _caller is null then
		raise exception 'Authentication required';
	end if;
	-- Whitelist, not a blacklist: a template added later is un-sendable here until
	-- someone deliberately adds it, which is the failure direction we want.
	if _event is null or _event not in ('ProposalCreatedStewards', 'ReconciliationFailed') then
		raise exception 'Not a steward notification: %', coalesce(_event, 'null');
	end if;

	insert into public.emails (event, scholar, sender, venue, email, subject, message, args)
	values (_event, null, _caller, null, public.steward_inbox(), null, null, to_jsonb(_args));
end;
$$;

alter function public.queue_steward_email (text, text[]) OWNER to "postgres";

revoke execute on function public.queue_steward_email (text, text[])
from
	public,
	anon;

grant execute on function public.queue_steward_email (text, text[]) to authenticated;

--------------------------------------
-- reconcile_ledger: same checks, one recipient.
--
-- Replaced wholesale because Postgres has no way to patch a function body. The only
-- change is the failure-notification INSERT at the end; everything above it is the
-- definition from 20260808010000_reconcile_ledger.sql, unmodified.
create or replace function public.reconcile_ledger () returns jsonb language plpgsql security definer
set
	search_path='' as $$
declare
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
	select count(*) into _replay
	from public.tokens t
	full outer join public.tokens_as_of() a on a.token = t.id
	where t.id is null
		or a.token is null
		or (t.scholar, t.venue, t.currency) is distinct from (a.scholar, a.venue, a.currency);

	-- 3. Each event's "previous owner" must match the prior event for that token.
	-- A break means a change happened that the trigger did not see — which a plain
	-- state comparison cannot detect, because the end state may still look right.
	select count(*) into _chain
	from (
		select
			e.prev_scholar, e.prev_venue,
			lag(e.scholar) over w as prior_scholar,
			lag(e.venue) over w as prior_venue,
			lag(e.seq) over w as prior_seq
		from public.token_events e
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
	select count(*) into _dangling
	from public.transactions x
	cross join lateral unnest(x.tokens) as tok(id)
	left join public.tokens t on t.id = tok.id
	where x.status = 'approved'
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

	insert into public.reconciliations (ok, result) values (_ok, _result);

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
