import { test, expect } from '@playwright/test';
import { login, logout } from '../src/routes/login';

test('currency page shows minters', async ({ page }) => {
	await page.goto('currency/c60c9fca-ad37-11f0-a9a1-57b72e1e85ac');

	// Expect there to be at least one minter.
	await expect(page.getByTestId('minter-0')).toBeVisible();

	// Expect there to be at least one venue
	await expect(page.getByTestId('venue-0')).toBeVisible();

	// Expect there to be a certain number of tokens in the table.
	await expect(page.getByTestId('stat-0')).toHaveText(/★[0-9]+ tokens/);
});

test('currency transactions page shows no transactions', async ({ page }) => {
	await page.goto('currency/c60c9fca-ad37-11f0-a9a1-57b72e1e85ac/transactions');

	// Expect there to be a feedback
	await expect(page.getByTestId('no-transactions')).toBeVisible();
});

test('currency transactions page shows minter transactions', async ({ page, context }) => {
	// Log in as minter
	await login('r1@uni.edu', page, context);

	// Visit the currency transactions page.
	await page.goto('currency/c60c9fca-ad37-11f0-a9a1-57b72e1e85ac/transactions');

	// Expect a transaction to be visible
	await expect(page.getByTestId('currency-transaction-0')).toBeVisible();

	// Log out
	await logout(page);
});
