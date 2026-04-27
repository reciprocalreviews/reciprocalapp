import { test, expect } from '@playwright/test';
import { login, logout } from '../src/routes/login';

test('a reviewer can bid on a paper and then see an unbid button', async ({ page, context }) => {
	await login('r1@uni.edu', page, context);

	await page.goto('/venue/c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6/submissions');
	await page.waitForLoadState('networkidle');

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
