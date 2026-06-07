import { execSync } from 'node:child_process';

/**
 * Reset the local Supabase database to the seed state before the suite runs.
 *
 * Unlike CI — which spins up a fresh, freshly-seeded Supabase instance for every
 * run — the local stack persists data between runs. Mutations a test makes
 * (spent tokens, accepted reviewer bids, edited submission costs, approved venue
 * proposals, …) therefore accumulate across runs and eventually break tests that
 * assume the seed values. Re-applying the seed here restores the invariant every
 * test relies on, so `npm run test:end` is reliable no matter how many times it
 * has been run before.
 *
 * Skipped in CI, where `supabase start` already brings up a fresh seeded DB and
 * a reset would only add time. We intentionally run `supabase db reset` directly
 * rather than `npm run reset` so we don't regenerate the checked-in
 * `src/data/database.ts` types on every test run.
 */
export default function globalSetup() {
	if (process.env.CI) return;
	console.log('[global-setup] Resetting local Supabase DB to seed state…');
	execSync('supabase db reset', { stdio: 'inherit' });
}
