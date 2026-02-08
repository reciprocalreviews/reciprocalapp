import { test, expect } from '@playwright/test';

test('landing page is visible', async ({ page }) => {
	await page.goto('/');

	// Expect a title "to contain" a substring.
	await expect(page).toHaveTitle('Reciprocal Reviews');

	// Expect the page title to be visible.
	await expect(page.getByTestId('page-header')).toHaveText('Reciprocal Reviews');
});
