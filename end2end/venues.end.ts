import { test, expect } from '@playwright/test';
import { SEED } from './test-utils';

test('active venues are shown', async ({ page }) => {
	await page.goto('/venues');

	// Expect there to be a single active venue link from seed data.
	await expect(page.getByTestId('venue-0')).toBeVisible();
});

test('inactive venues are listed separately, with their message, and still link', async ({
	page
}) => {
	await page.goto('/venues');

	// Found by name rather than by index: approving a proposal creates an inactive venue,
	// so another spec running alongside this one can add rows to this list.
	const link = page.getByRole('link', { name: SEED.inactiveVenue.title });
	await expect(link).toHaveCount(1);
	await expect(link).toHaveAttribute('data-testid', /^inactive-venue-/);
	await expect(link).toHaveAttribute('href', `/venue/${SEED.inactiveVenue.path}`);
	await expect(page.getByText(SEED.inactiveVenue.message)).toBeVisible();

	// A visitor who follows it reaches the closed venue's page, not an error.
	await link.click();
	await expect(page.getByTestId('venue-inactive-notice')).toBeVisible();
});
