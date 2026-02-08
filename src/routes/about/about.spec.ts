import { test, expect } from '@playwright/test';

test('the about page shows stewards', async ({ page }) => {
	await page.goto('/about');

	// Expect the about page to have a steward from seed data.
	await expect(page.getByTestId('steward-0')).toBeVisible();
});
