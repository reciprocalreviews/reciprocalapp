import { test, expect } from '@playwright/test';

test('currency page shows minters', async ({ page }) => {
	await page.goto('currency/c60c9fca-ad37-11f0-a9a1-57b72e1e85ac');

	// Expect there to be at least one minter.
	await expect(page.getByTestId('minter-0')).toBeVisible();

	// Expect there to be at least one venue
	await expect(page.getByTestId('venue-0')).toBeVisible();

	// Expect there to be a certain number of tokens in the table.
	await expect(page.getByTestId('stat-0')).toHaveText(/★[0-9]+ tokens/);
});
