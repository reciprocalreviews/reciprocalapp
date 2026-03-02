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

	// Expected two volunteer rows
	await expect(page.getByTestId('admin-0')).toBeVisible();
	await expect(page.getByTestId('commitment-0')).toBeVisible();

	// Expect a token count
	await expect(page.getByTestId('currency-0')).toBeVisible();

	// Log out
	await logout(page);
});

test('anonymous visitor should not see transactions', async ({ page }) => {
	// Go to the transactions page
	await page.goto('scholar/b8a805bf-0aae-4443-9185-de019a8715cb/transactions');

	// Expect a transaction to be visible
	await expect(page.getByTestId('no-transactions')).toBeVisible();
});

test('scholar should see their transactions', async ({ page, context }) => {
	// Log in as the author with a transaction
	await login('author1@uni.edu', page, context);

	// Go to the transactions page
	await page.goto('scholar/b8a805bf-0aae-4443-9185-de019a8715cb/transactions');

	// Expect a transaction to be visible
	await expect(page.getByTestId('scholar-transaction-0')).toBeVisible();

	// Log out
	await logout(page);
});
