import { test, expect } from '@playwright/test';

test('landing page is visible', async ({ page }) => {
	await page.goto('/');

	// Expect the title to be Reciprocal Reviews.
	await expect(page).toHaveTitle('Reciprocal Reviews');

	await expect(page.getByTestId('page-header')).toHaveText('Reciprocal Reviews');

	// Exactly one brand mark, in the nav, where it replaced the word "Home" (#176). The
	// landing page used to carry a second one beside its own title, which on the one page
	// whose title IS the wordmark read as a mistake rather than as emphasis.
	await expect(page.getByTestId('nav-logo')).toBeVisible();
	await expect(page.getByTestId('logo')).toHaveCount(0);

	// And here it does not offer to take you anywhere, because here is where it goes: no
	// href and `aria-current` instead, the same rule Link.svelte applies to every other
	// link in the chrome.
	const mark = page.locator('.home');
	await expect(mark).not.toHaveAttribute('href');
	await expect(mark).toHaveAttribute('aria-current', 'page');
});

test('the brand mark links home from anywhere else', async ({ page }) => {
	await page.goto('/venues');
	await page.waitForLoadState('networkidle');

	await expect(page.getByRole('link', { name: 'Home' })).toHaveAttribute('href', '/');
});
