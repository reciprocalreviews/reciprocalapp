import { test, expect } from '@playwright/test';

test('landing page is visible', async ({ page }) => {
	await page.goto('/');

	// Expect the title to be Reciprocal Reviews.
	await expect(page).toHaveTitle('Reciprocal Reviews');

	// Expect the header to also be Reciprocal Reviews.
	await expect(page.getByTestId('page-header')).toHaveText('Reciprocal Reviews');
});
