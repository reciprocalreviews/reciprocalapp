import { test, expect } from '@playwright/test';
import { login, logout } from '../src/routes/login';

test('anonymous scholars should see submission types and all roles', async ({ page }) => {
	await page.goto('/venue/c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6');

	await expect(page.getByTestId('submission-type-0'), "Expect a submission type").toBeVisible();

	await expect(page.getByTestId('role-Editor'), "Expect an editor role").toBeVisible();
	await expect(page.getByTestId('role-Associate Editor'), "Expect an associate editor role").toBeVisible();
	await expect(page.getByTestId('role-Reviewer'), "Expect a reviewer role").toBeVisible();
});

test('a volunteer should see they have volunteered', async ({ page, context }) => {
	await login('r1@uni.edu', page, context);

	await page.goto('/venue/c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6');

	await expect(page.getByTestId('volunteered-for-role'), "Expect an option to stop volunteering for the role").toBeVisible();

	await page.goto('/venue/c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6/volunteers');

	await expect(page.getByTestId('volunteer-row-0-0'), "Expect an editor volunteer").toBeVisible();
	await expect(page.getByTestId('volunteer-row-1-0'), "Expect an associate editor volunteer").toBeVisible();
	await expect(page.getByTestId('volunteer-row-2-0'), "Expect a first reviewer volunteer").toBeVisible();
	await expect(page.getByTestId('volunteer-row-2-1'), "Expect a second reviewer volunteer").toBeVisible();
	await expect(page.getByTestId('volunteer-row-2-2'), "Expect a third reviewer volunteer").toBeVisible();

	await logout(page);
});

test('a reviewer can bid on a paper and then see an unbid button', async ({ page, context }) => {
	await login('r1@uni.edu', page, context);

	await page.goto('/venue/c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6/submissions');

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
});

test('an editor should see editor specific things', async ({ page, context }) => {
	await login('editor@uni.edu', page, context);

	await page.goto('/venue/c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6');

	// Expect there to be a single active venue link from seed data.
	await expect(page.getByTestId('new-submission-type'), "Expect an editor to a new submission type button").toBeVisible();

	// Visit settings
	await page.goto('/venue/c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6/settings');

	// Expect various controls for editing settings.
	await expect(page.getByTestId('new-role-name'), "Expect a new role name field").toBeVisible();
	await expect(page.getByTestId('setup-card'), "Expect a setup card").toBeVisible();
	await expect(page.getByTestId('inactive-checkbox'), "Expect an inactive checkbox").toBeVisible();

	// Visit submissions
	await page.goto('/venue/c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6/submissions');

	// Expect a submission on the submissions page
	await expect(page.getByTestId('submission-0'), "Expect a first submission").toBeVisible();

	// Visit the submission page
	await page.goto(
		'/venue/c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6/submission/c61a1f5a-ad3a-11f0-9805-3f4d2f5e3c12'
	);

	// Expect the form for adding a new assignment
	await expect(page.getByTestId('new-assignment'), "Expect a new assignment button").toBeVisible();

	// Visit the transactions page
	await page.goto('/venue/c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6/transactions');

	// Expect 6 tokens from the seed data.
	await expect(page.getByTestId('venue-transaction-0', "Expect transaction 1")).toBeVisible();
	await expect(page.getByTestId('venue-transaction-1', "Expect transaction 2")).toBeVisible();
	await expect(page.getByTestId('venue-transaction-2', "Expect transaction 3")).toBeVisible();
	await expect(page.getByTestId('venue-transaction-3', "Expect transaction 4")).toBeVisible();
	await expect(page.getByTestId('venue-transaction-4', "Expect transaction 5")).toBeVisible();
	await expect(page.getByTestId('venue-transaction-5', "Expect transaction 6")).toBeVisible();

	await logout(page);
});
