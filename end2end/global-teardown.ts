import { sql } from './test-utils';

/**
 * Assert that the suite left the token ledger reconstructible.
 *
 * `public.token_events` is written by a trigger on `public.tokens`, so it records
 * *every* write to that table — including one a test makes with raw SQL. A direct
 * `delete` logs a burn for each row, and those tokens then replay as owned by
 * nobody; a direct `update` moves value with no transaction to attribute it to.
 * Neither breaks any Playwright assertion, so for a while the only thing that
 * noticed was `npm run test:rls`, one suite later, where four pgTAP invariants
 * failed on a tree where nothing was actually wrong (#152). CI never saw it at
 * all, because its RLS and Playwright jobs each boot their own Supabase.
 *
 * Checking here puts the failure in the run that caused it, next to the test that
 * did. Both queries are read-only by design: `reconcile_ledger()` would say the
 * same thing, but it also appends to `public.reconciliations` and can mail the
 * steward inbox, and a test suite should not be writing to either.
 *
 * Safe to run after the tests: Playwright stops the `webServer` before this, but
 * that only kills `vite preview` — `start:test` leaves the Supabase containers up,
 * so psql is still reachable.
 */
export default function globalTeardown() {
	// One line, deliberately: sql() hands the statement to `docker exec` as a
	// JSON-quoted argument, so a newline in the template literal arrives at psql as
	// a literal backslash-n and it reports a syntax error.
	const replay = `select count(*) from public.tokens t full outer join public.tokens_as_of() a on a.token = t.id where t.id is null or a.token is null or (t.scholar, t.venue, t.currency) is distinct from (a.scholar, a.venue, a.currency)`;
	const unattributedMoves = `select count(*) from public.token_events where op = 'move' and txn is null`;
	const [mismatches, unattributed] = sql(`select (${replay}), (${unattributedMoves});`)
		.split('|')
		.map((n) => Number(n.trim()));

	if (mismatches > 0 || unattributed > 0)
		throw new Error(
			`[global-teardown] The token ledger no longer reconstructs: ${mismatches} replay mismatch(es), ${unattributed} unattributed move(s).\n` +
				`A test wrote public.tokens directly instead of moving value through the RPCs. Use asScholar() from end2end/test-utils.ts to call mint_tokens / transfer_tokens / approve_transaction as the app does, and restore what you take in a finally.\n` +
				`(If tests also failed above, this may just be their fallout — a run that dies mid-transfer leaves the same trace.)`
		);
}
