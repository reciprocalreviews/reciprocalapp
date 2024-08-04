import { test, expect } from '@playwright/test';

test('has window title', async ({ page }) => {
	await page.goto('/');

	// Expect a title "to contain" a substring.
	await expect(page).toHaveTitle('Reciprocal Reviews');
});
