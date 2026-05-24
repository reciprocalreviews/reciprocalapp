import { execSync } from 'child_process';
import { test, expect } from '@playwright/test';
import { login, logout } from '../src/routes/login';

const VENUE_ID = 'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6';
// r4 (Manny Script) — has a Reviewer volunteer record and is neither author
// of nor approved-Reviewer on any seeded submission, so they always have
// biddable papers in the venue's submissions list.
const BIDDER_EMAIL = 'r4@uni.edu';
const BIDDER_ID = '7ff8621a-cbe0-4789-bbee-f008d38c4aca';

function sql(statement: string): string {
	return execSync(
		`docker exec supabase_db_reciprocalapp psql -U postgres -d postgres -t -A -q -c ${JSON.stringify(statement)}`,
		{ encoding: 'utf-8' }
	).trim();
}

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
	await login('editor@uni.edu', page, context);
	await page.goto(`/venue/${VENUE_ID}/submissions`);
	await page.waitForLoadState('networkidle');

	const rows = page.locator('tr[data-testid^="submission-"]');
	const filter = page.getByTestId('submissions-filter');

	// Baseline: at least 4 seeded submissions for this venue.
	const baseline = await rows.count();
	expect(baseline).toBeGreaterThanOrEqual(4);

	// Filter by author name "Foot" (Foot Note authors TOK-2025-001 and -004).
	await filter.fill('Foot');
	await expect.poll(async () => rows.count()).toBe(2);

	// Filter by reviewer-only name "Manny" (Manny Script has bid as Reviewer
	// on TOK-2025-001 and is not an author of anything) — proves the new
	// reviewer branch matches. The editor is the Editor on TOK-2025-001, so
	// RLS lets them see the bid assignment.
	await filter.fill('Manny');
	await expect.poll(async () => rows.count()).toBe(1);

	// Filter by "Rigor" — Rigor Russ authors -002 and -003 AND is the seeded
	// Reviewer on -001 and -004, so 4 rows should match (covers both paths).
	await filter.fill('Rigor');
	await expect.poll(async () => rows.count()).toBe(4);

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
