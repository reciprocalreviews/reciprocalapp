import { test, expect } from '@playwright/test';

test('active venues are shown', async ({ page }) => {
	await page.goto('/venues');

	// Expect the page title to be visible.
	await expect(page.getByTestId('venue-0')).toBeVisible();
});
