import { execSync } from 'node:child_process';
import { sql } from './test-utils';

/**
 * Prepare the local Supabase database for the suite.
 *
 * Two things happen here, for unrelated reasons.
 *
 * 1. Unschedule the `reconcile-email-delivery` cron job. This runs in CI too, and must.
 *    The suite is served by `start:test`, which deliberately omits `edge-runtime`, so
 *    every send_email() post to the `resend` function fails. That used to be invisible —
 *    the post was best effort and swallowed its own failure — but delivery is recorded
 *    now (#27), so the reconciler would truthfully mark each of those emails `failed`,
 *    and any test touching the verification UI would start seeing the "we couldn't
 *    deliver" notice depending on whether the job happened to fire mid-run. That is a
 *    nondeterministic failure caused by a monitoring job doing its job correctly, which
 *    is the worst kind to debug. The delivery-failure surface is tested deterministically
 *    instead, by writing `delivery` directly — see emailVerification.end.ts.
 *
 * 2. Reset the database to the seed state. Unlike CI — which spins up a fresh, freshly-
 *    seeded Supabase instance for every run — the local stack persists data between runs.
 *    Mutations a test makes (spent tokens, accepted reviewer bids, edited submission
 *    costs, approved venue proposals, …) therefore accumulate across runs and eventually
 *    break tests that assume the seed values. Re-applying the seed restores the invariant
 *    every test relies on, so `npm run test:end` is reliable no matter how many times it
 *    has been run before. Skipped in CI, where `supabase start` already brings up a fresh
 *    seeded DB and a reset would only add time. We intentionally run `supabase db reset`
 *    directly rather than `npm run reset` so we don't regenerate the checked-in
 *    `src/data/database.ts` types on every test run.
 *
 * The unschedule comes first, and outside the CI early return, because the reset re-runs
 * the migrations — which re-create the job.
 */
export default function globalSetup() {
	if (process.env.CI) {
		unscheduleDeliveryReconciler();
		return;
	}
	console.log('[global-setup] Resetting local Supabase DB to seed state…');
	execSync('supabase db reset', { stdio: 'inherit' });
	unscheduleDeliveryReconciler();
}

/** Stop the delivery reconciler for the duration of the suite. Guarded, because
 * cron.unschedule raises on a job that isn't there. */
function unscheduleDeliveryReconciler() {
	console.log('[global-setup] Unscheduling reconcile-email-delivery for the test run…');
	sql(
		`select cron.unschedule('reconcile-email-delivery') where exists (select 1 from cron.job where jobname = 'reconcile-email-delivery')`
	);
}
