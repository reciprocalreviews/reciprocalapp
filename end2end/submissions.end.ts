import { test, expect } from '@playwright/test';
import { login, logout } from '../src/routes/login';
import { SEED, sql } from './test-utils';

const VENUE_ID = SEED.venue;
// r4 (Manny Script) — has a Reviewer volunteer record and is neither author
// of nor approved-Reviewer on any seeded submission, so they always have
// biddable papers in the venue's submissions list.
const BIDDER_EMAIL = SEED.scholars.r4.email;
const BIDDER_ID = SEED.scholars.r4.id;

test('a reviewer can bid on a paper and then see an unbid button', async ({ page, context }) => {
	// Reset state: drop any of Manny's pending Reviewer bids so the page
	// loads with no unbid buttons, and the post-click assertion is unambiguous.
	sql(
		`delete from public.assignments where scholar = '${BIDDER_ID}' and venue = '${VENUE_ID}' and bid = true and approved = false;`
	);

	try {
		await login(BIDDER_EMAIL, page, context);
		await page.goto(`/venue/${VENUE_ID}/submissions`);
		await page.waitForLoadState('networkidle');

		// No bids placed yet → no unbid buttons.
		await expect(page.getByTestId(/^unbid-/)).toHaveCount(0);

		// Bid on the first paper that has a bid button.
		const firstBidButton = page.getByTestId(/^bid-/).first();
		await expect(firstBidButton, 'Expect a bid button to be visible').toBeVisible();
		await firstBidButton.click();

		// After bidding, an unbid button should appear.
		await expect(
			page.getByTestId(/^unbid-/).first(),
			'Expect an unbid button to appear after bidding'
		).toBeVisible();

		await logout(page);
	} finally {
		// Cleanup: drop the bid this test created so subsequent runs and other
		// tests aren't perturbed.
		sql(
			`delete from public.assignments where scholar = '${BIDDER_ID}' and venue = '${VENUE_ID}' and bid = true and approved = false;`
		);
	}
});

test('editor filters submissions by author name, reviewer name, title, and external ID', async ({
	page,
	context
}) => {
	// Query expected counts from the DB rather than hard-coding them, because
	// earlier tests in the full suite may have created additional submissions
	// (e.g. submission.end.ts creates one authored by author1@uni.edu = Foot
	// Note). Reviewer counts are likewise computed live.
	const FOOT_ID = sql(`select id from public.scholars where email = 'author1@uni.edu';`);
	const RIGOR_ID = sql(`select id from public.scholars where email = 'r1@uni.edu';`);
	const MANNY_ID = sql(`select id from public.scholars where email = 'r4@uni.edu';`);
	const footAuthoredCount = Number(
		sql(
			`select count(*) from public.submissions where venue = '${VENUE_ID}' and '${FOOT_ID}' = any(authors);`
		)
	);
	// "Rigor" matches submissions where r1 is author OR a visible assignee.
	const rigorMatchCount = Number(
		sql(
			`select count(distinct s.id) from public.submissions s left join public.assignments a on a.submission = s.id and a.scholar = '${RIGOR_ID}' where s.venue = '${VENUE_ID}' and ('${RIGOR_ID}' = any(s.authors) or a.id is not null);`
		)
	);
	const mannyMatchCount = Number(
		sql(
			`select count(distinct s.id) from public.submissions s left join public.assignments a on a.submission = s.id and a.scholar = '${MANNY_ID}' where s.venue = '${VENUE_ID}' and ('${MANNY_ID}' = any(s.authors) or a.id is not null);`
		)
	);

	await login('editor@uni.edu', page, context);
	await page.goto(`/venue/${VENUE_ID}/submissions`);
	await page.waitForLoadState('networkidle');

	const rows = page.locator('tr[data-testid^="submission-"]');
	const filter = page.getByTestId('submissions-filter');

	// Baseline: the seed has 4 submissions; later tests may add more.
	const baseline = await rows.count();
	expect(baseline).toBeGreaterThanOrEqual(4);

	// Filter by author name "Foot" (Foot Note authors TOK-2025-001 and -004 in
	// the seed; other tests may add more authored by them).
	await filter.fill('Foot');
	await expect.poll(async () => rows.count()).toBe(footAuthoredCount);

	// Filter by reviewer-only name "Manny" — Manny Script bids on TOK-2025-001
	// in the seed and isn't an author. Proves the reviewer-match branch works.
	await filter.fill('Manny');
	await expect.poll(async () => rows.count()).toBe(mannyMatchCount);

	// Filter by "Rigor" — Rigor Russ authors TOK-2025-002 and -003 AND is the
	// seeded Reviewer on -001 and -004 (covers both the author and reviewer
	// match paths).
	await filter.fill('Rigor');
	await expect.poll(async () => rows.count()).toBe(rigorMatchCount);

	// Title-fragment match still works (regression).
	await filter.fill('Windmill');
	await expect.poll(async () => rows.count()).toBe(1);

	// External-ID match still works (regression).
	await filter.fill('TOK-2025-003');
	await expect.poll(async () => rows.count()).toBe(1);

	// Clearing the filter restores all rows.
	await filter.fill('');
	await expect.poll(async () => rows.count()).toBe(baseline);

	await logout(page);
});
