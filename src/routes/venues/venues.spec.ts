import { test, expect } from '@playwright/test';

test('active venues are shown', async ({ page }) => {
	await page.goto('/venues');

	// Expect there to be a single active venue link from seed data.
	await expect(page.getByTestId('venue-0')).toBeVisible();
});
