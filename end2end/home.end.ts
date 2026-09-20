import { test, expect } from '@playwright/test';

test('landing page is visible', async ({ page }) => {
	await page.goto('/');

	// Expect the title to be Reciprocal Reviews.
	await expect(page).toHaveTitle('Reciprocal Reviews');

	// Expect the header to also be Reciprocal Reviews. The brand mark beside it is an
	// inline SVG, so it contributes no text of its own; it is asserted separately.
	await expect(page.getByTestId('page-header')).toHaveText('Reciprocal Reviews');
	await expect(page.getByTestId('logo')).toBeVisible();

	// The mark is in the nav too, where it replaced the word "Home" (#176), which is why
	// it needs a test id of its own: two elements answering to `logo` would be a
	// strict-mode failure rather than an ambiguity Playwright resolves.
	await expect(page.getByTestId('nav-logo')).toBeVisible();
	await expect(page.getByRole('link', { name: 'Home' })).toHaveAttribute('href', '/');
});
