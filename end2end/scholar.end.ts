import { test, expect } from '@playwright/test';
import { login, logout } from '../src/routes/login';

test('the read-only scholar profile page should show volunteering roles', async ({ page }) => {
	await page.goto('/scholar/d181d165-8b6a-4d79-ad28-a9aece21d813');

	// Expect the seeded scholar to have two commitments.
	await expect(page.getByTestId('admin-0')).toBeVisible();
	await expect(page.getByTestId('commitment-0')).toBeVisible();
});

test('the logged in scholar should see many things', async ({ page, context }) => {
	// Log in as editor
	await login('editor@uni.edu', page, context);

	// Expect a seeded review
	await expect(page.getByTestId('review-0')).toBeVisible();

	// Log out
	await logout(page);
});
