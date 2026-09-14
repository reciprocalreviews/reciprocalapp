import { test, expect } from '@playwright/test';
import { login, logout } from '../src/routes/login';
import { SEED, sql } from './test-utils';

const VENUE_ID = SEED.venue;
const VENUE_PATH = SEED.venuePath;
// The reviewer-only scholar `filters.uniqueReviewer` picks out: has a Reviewer
// volunteer record and is neither author of nor approved-Reviewer on any seeded
// submission, so they always have biddable papers in the submissions list.
const BIDDER_EMAIL = SEED.scholars.r4.email;
const BIDDER_ID = SEED.scholars.r4.id;

test('a reviewer can bid on a paper and then see an unbid button', async ({ page, context }) => {
	// Reset state: drop any of that bidder's pending Reviewer bids so the page
	// loads with no unbid buttons, and the post-click assertion is unambiguous.
	sql(
		`delete from public.assignments where scholar = '${BIDDER_ID}' and venue = '${VENUE_ID}' and bid = true and approved = false;`
	);

	try {
		await login(BIDDER_EMAIL, page, context);
		await page.goto(`/venue/${VENUE_PATH}/submissions`);
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
	// (e.g. submission.end.ts creates one authored by author1). Reviewer counts
	// are likewise computed live.
	const AUTHOR_ID = SEED.scholars.author1.id;
	const BOTH_ID = SEED.scholars.r1.id;
	const REVIEWER_ID = SEED.scholars.r4.id;
	const authoredCount = Number(
		sql(
			`select count(*) from public.submissions where venue = '${VENUE_ID}' and '${AUTHOR_ID}' = any(authors);`
		)
	);
	// Matches submissions where r1 is author OR a visible assignee.
	const bothMatchCount = Number(
		sql(
			`select count(distinct s.id) from public.submissions s left join public.assignments a on a.submission = s.id and a.scholar = '${BOTH_ID}' where s.venue = '${VENUE_ID}' and ('${BOTH_ID}' = any(s.authors) or a.id is not null);`
		)
	);
	const reviewerMatchCount = Number(
		sql(
			`select count(distinct s.id) from public.submissions s left join public.assignments a on a.submission = s.id and a.scholar = '${REVIEWER_ID}' where s.venue = '${VENUE_ID}' and ('${REVIEWER_ID}' = any(s.authors) or a.id is not null);`
		)
	);

	await login('editor@uni.edu', page, context);
	await page.goto(`/venue/${VENUE_PATH}/submissions`);
	await page.waitForLoadState('networkidle');

	const rows = page.locator('tr[data-testid^="submission-"]');
	const filter = page.getByTestId('submissions-filter');

	// Baseline: the seed has 4 submissions; later tests may add more.
	const baseline = await rows.count();
	expect(baseline).toBeGreaterThanOrEqual(4);

	// Filter by an author's name fragment (they author seeded submissions; other
	// tests may add more authored by them).
	await filter.fill(SEED.filters.uniqueAuthor);
	await expect.poll(async () => rows.count()).toBe(authoredCount);

	// Filter by a reviewer-only name fragment — that scholar bids but authors
	// nothing. Proves the reviewer-match branch works.
	await filter.fill(SEED.filters.uniqueReviewer);
	await expect.poll(async () => rows.count()).toBe(reviewerMatchCount);

	// Filter by a scholar who both authors submissions AND reviews others,
	// covering both the author and reviewer match paths at once.
	await filter.fill(SEED.filters.authorAndReviewer);
	await expect.poll(async () => rows.count()).toBe(bothMatchCount);

	// Title-fragment match still works (regression).
	await filter.fill(SEED.filters.uniqueTitleWord);
	await expect.poll(async () => rows.count()).toBe(1);

	// External-ID match still works (regression).
	await filter.fill(SEED.submissions.tok003.externalId);
	await expect.poll(async () => rows.count()).toBe(1);

	// Clearing the filter restores all rows.
	await filter.fill('');
	await expect.poll(async () => rows.count()).toBe(baseline);

	await logout(page);
});

// The submissions list is where a bidder decides what to bid on, and at a venue
// whose roles are anonymized it must not hand back the author identities it is
// withholding. The seeded Reviewer role is biddable with anonymous_authors set,
// and the bidder above is neither an author of nor an approved Reviewer on any
// seeded submission, so every row is anonymized from their seat.
test('a bidder at an anonymized venue sees locks, not authors or manuscript IDs', async ({
	page,
	context
}) => {
	const LOCK = '\u{1F512}\uFE0E';
	const EM_DASH = '\u2014';
	// The one submission whose title carries `uniqueTitleWord`, so the row can be
	// picked out by title while its manuscript ID is withheld.
	const ANON_SUBMISSION = SEED.submissions.tok002;
	const TITLE_WORD = SEED.filters.uniqueTitleWord;
	// Blank one submission's expertise so the "none provided" cell has a subject.
	// The seed fills every submission's expertise, and the detail page writes
	// null back for empty input, so null is the state to reproduce.
	const priorExpertise = sql(
		`select coalesce(expertise, '') from public.submissions where externalid = '${ANON_SUBMISSION.externalId}';`
	);
	sql(
		`update public.submissions set expertise = null where externalid = '${ANON_SUBMISSION.externalId}';`
	);

	try {
		await login(BIDDER_EMAIL, page, context);
		await page.goto(`/venue/${VENUE_PATH}/submissions`);
		await page.waitForLoadState('networkidle');

		const rows = page.locator('tr[data-testid^="submission-"]');
		const baseline = await rows.count();
		expect(baseline).toBeGreaterThanOrEqual(4);

		// Authors and manuscript ID are both withheld, and say so with a lock.
		const firstRow = rows.first();
		await expect(firstRow.getByTitle('anonymized')).toHaveCount(2);
		await expect(firstRow.getByTitle('anonymized').first()).toHaveText(LOCK);

		// No manuscript ID leaks into any row.
		await expect(page.getByText(SEED.submissionIdPrefix, { exact: false })).toHaveCount(0);

		// The title stays visible: it is what a bidder judges interest by, and
		// what they recognize a conflict from.
		await expect(page.getByText(TITLE_WORD, { exact: false }).first()).toBeVisible();

		// Expertise nobody supplied reads as none provided, not as a blank cell.
		const anonRow = rows.filter({ hasText: TITLE_WORD });
		await expect(anonRow.getByText(EM_DASH, { exact: true })).toHaveCount(1);

		// The search box must not become the side channel the ID column closed:
		// a guessed manuscript ID confirms nothing.
		const filter = page.getByTestId('submissions-filter');
		await filter.fill(ANON_SUBMISSION.externalId);
		await expect.poll(async () => rows.count()).toBe(0);

		// A title fragment still filters, so search is gated rather than broken.
		await filter.fill(TITLE_WORD);
		await expect.poll(async () => rows.count()).toBe(1);

		await logout(page);
	} finally {
		sql(
			`update public.submissions set expertise = ${priorExpertise === '' ? 'null' : `'${priorExpertise}'`} where externalid = '${ANON_SUBMISSION.externalId}';`
		);
	}
});
