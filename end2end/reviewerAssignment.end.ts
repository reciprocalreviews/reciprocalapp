import { test, expect } from '@playwright/test';
import { login, logout } from '../src/routes/login';

const VENUE_ID = 'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6';
const SUBMISSION_EXTERNAL_ID = 'TOK-2025-001';
const SUBMISSION_ID = 'c61a1f5a-ad3a-11f0-9805-3f4d2f5e3c12';

const APPROVE_BID_TIP =
	'Accept this bid, assigning this scholar to this role for this submission';
const UNASSIGN_TIP = 'Remove this assignment';

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
