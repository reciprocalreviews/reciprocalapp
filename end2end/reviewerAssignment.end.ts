import { test, expect } from '@playwright/test';
import { execSync } from 'child_process';
import { login, logout } from '../src/routes/login';

const VENUE_ID = 'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6';
const SUBMISSION_EXTERNAL_ID = 'TOK-2025-001';
const SUBMISSION_ID = 'c61a1f5a-ad3a-11f0-9805-3f4d2f5e3c12';
const SUBMISSION_002 = 'c61a1f5a-ad3a-11f0-9805-3f4d2f5e3c13';
const REVIEWER_ROLE = 'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81';
const MANNY_ID = '7ff8621a-cbe0-4789-bbee-f008d38c4aca';

const APPROVE_BID_TIP =
	'Accept this bid, assigning this scholar to this role for this submission';
const APPROVE_ANYWAY_TIP = 'Assign this scholar despite the load warning';
const UNASSIGN_TIP = 'Remove this assignment';

function sql(statement: string): string {
	return execSync(
		`docker exec supabase_db_reciprocalapp psql -U postgres -d postgres -t -A -q -c ${JSON.stringify(statement)}`,
		{ encoding: 'utf-8' }
	).trim();
}

test('AE assigns two reviewer bids and bidding closes', async ({ page, context }) => {
	await login('ae@uni.edu', page, context);

	// Submissions list shows TOK-2025-001.
	await page.goto(`/venue/${VENUE_ID}/submissions`);
	await page.waitForLoadState('networkidle');
	await expect(page.getByText(SUBMISSION_EXTERNAL_ID)).toBeVisible();

	// Open the submission detail page.
	await page.goto(`/venue/${VENUE_ID}/submission/${SUBMISSION_ID}`);
	await page.waitForLoadState('networkidle');

	// Two pending bids waiting for assignment, plus one already-approved Reviewer
	// (Rigor Russ from the seed) producing one Unassign button.
	await expect(page.getByRole('button', { name: APPROVE_BID_TIP })).toHaveCount(2);
	await expect(page.getByRole('button', { name: UNASSIGN_TIP })).toHaveCount(1);

	// Assign the first bid; one fewer pending, one more Unassign.
	await page.getByRole('button', { name: APPROVE_BID_TIP }).first().click();
	await expect(page.getByRole('button', { name: APPROVE_BID_TIP })).toHaveCount(1);
	await expect(page.getByRole('button', { name: UNASSIGN_TIP })).toHaveCount(2);

	// Assign the remaining bid; no pending bids left, three Unassigns.
	await page.getByRole('button', { name: APPROVE_BID_TIP }).first().click();
	await expect(page.getByRole('button', { name: APPROVE_BID_TIP })).toHaveCount(0);
	await expect(page.getByRole('button', { name: UNASSIGN_TIP })).toHaveCount(3);

	// Back on the submissions list, bidding for that submission's Reviewer role
	// should now be closed (3 approved Reviewer assignments meets desired=3).
	await page.goto(`/venue/${VENUE_ID}/submissions`);
	await page.waitForLoadState('networkidle');
	await expect(page.getByText('bidding closed')).toBeVisible();

	await logout(page);
});

test('over-cap bidder shows load indicator and requires confirm to assign', async ({
	page,
	context
}) => {
	// Put Manny Script at 1 active assignment with cap=1 on Reviewer so that
	// their existing bid on TOK-2025-001 renders as over-cap. Resets any
	// state the previous test in this file may have left behind so the test
	// is self-contained.
	sql(
		`update public.volunteers set papers = 1 where scholarid = '${MANNY_ID}' and roleid = '${REVIEWER_ROLE}';`
	);
	sql(
		`update public.assignments set bid = true, approved = false where scholar = '${MANNY_ID}' and submission = '${SUBMISSION_ID}';`
	);
	sql(
		`delete from public.assignments where scholar = '${MANNY_ID}' and submission = '${SUBMISSION_002}';`
	);
	sql(
		`insert into public.assignments (venue, submission, scholar, role, bid, approved, completed) values ('${VENUE_ID}', '${SUBMISSION_002}', '${MANNY_ID}', '${REVIEWER_ROLE}', false, true, false);`
	);

	try {
		await login('ae@uni.edu', page, context);
		await page.goto(`/venue/${VENUE_ID}/submission/${SUBMISSION_ID}`);
		await page.waitForLoadState('networkidle');

		// Manny's bid row exists; the load indicator on it reads "1 / 1" and is
		// over-cap (CSS class flags it red/bold).
		const mannyRow = page.locator('tr:has-text("Manny")');
		const load = mannyRow.locator('[data-testid="papers-load"]');
		await expect(load).toHaveText('1 / 1');
		await expect(load).toHaveClass(/over-cap/);

		// The approve button on the over-cap bid is now Button's warn-style
		// confirm — its accessible name comes from the approveAnyway tip, not
		// the regular approveBid tip.
		const approveAnyway = mannyRow.getByRole('button', { name: APPROVE_ANYWAY_TIP });
		await expect(approveAnyway).toBeVisible();

		// First click enters confirm mode; the assignment should NOT yet be approved.
		await approveAnyway.click();
		expect(
			sql(
				`select approved::text from public.assignments where scholar = '${MANNY_ID}' and submission = '${SUBMISSION_ID}';`
			)
		).toBe('false');

		// Second click commits — assignment flips to approved.
		await mannyRow.getByRole('button', { name: 'Assign over cap?' }).click();
		await expect
			.poll(() =>
				sql(
					`select approved::text from public.assignments where scholar = '${MANNY_ID}' and submission = '${SUBMISSION_ID}';`
				)
			)
			.toBe('true');

		// Dismiss the success toasts that approval queues (one per email recipient)
		// so they don't intercept the logout click.
		const dismissButtons = page.locator('[data-testid="feedback-success"] button');
		while ((await dismissButtons.count()) > 0) {
			await dismissButtons.first().click();
		}
		await logout(page);
	} finally {
		// Restore Manny to a seed-equivalent state so downstream tests in the
		// full suite don't see leftover approvals or an unexpected papers cap.
		sql(
			`update public.volunteers set papers = null where scholarid = '${MANNY_ID}' and roleid = '${REVIEWER_ROLE}';`
		);
		sql(
			`update public.assignments set bid = true, approved = false where scholar = '${MANNY_ID}' and submission = '${SUBMISSION_ID}';`
		);
		sql(
			`delete from public.assignments where scholar = '${MANNY_ID}' and submission = '${SUBMISSION_002}';`
		);
	}
});
