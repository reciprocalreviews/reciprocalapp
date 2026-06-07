import { test, expect } from '@playwright/test';
import { execSync } from 'child_process';
import { login, logout } from '../src/routes/login';

const CURRENCY_ID = 'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac'; // Epistemology
const AUTHOR1_EMAIL = 'author1@uni.edu';
const AUTHOR1_ID = 'b8a805bf-0aae-4443-9185-de019a8715cb'; // holds 100 Epistemology tokens (seed)
const AUTHOR2_EMAIL = 'author2@uni.edu';
const AUTHOR2_ID = 'b8a805bf-0aae-4443-9185-de019a8715ec';
const AUTHOR2_ORCID = '0000-0001-2345-6795';

function sql(statement: string): string {
	// `-q` suppresses the trailing command tag so callers using RETURNING get
	// back only the value.
	return execSync(
		`docker exec supabase_db_reciprocalapp psql -U postgres -d postgres -t -A -q -c ${JSON.stringify(statement)}`,
		{ encoding: 'utf-8' }
	).trim();
}

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

test('scholar edits their availability and status, persisting on reload', async ({
	page,
	context
}) => {
	test.setTimeout(60_000);

	await login(AUTHOR1_EMAIL, page, context);
	await page.goto(`/scholar/${AUTHOR1_ID}`);
	await page.waitForLoadState('networkidle');

	// Toggle availability. Read the current value first so the test is
	// idempotent across re-runs (we flip relative to whatever is stored).
	const availableBefore = sql(`select available from public.scholars where id = '${AUTHOR1_ID}';`);
	const expectedAvailable = availableBefore === 't' ? 'f' : 't';

	const availableCheckbox = page.getByTestId('available-checkbox');
	await availableCheckbox.waitFor();
	await availableCheckbox.click();

	// The change handler persists immediately (no separate save).
	await expect
		.poll(() => sql(`select available from public.scholars where id = '${AUTHOR1_ID}';`))
		.toBe(expectedAvailable);

	// The new state survives a reload.
	await page.reload();
	await page.waitForLoadState('networkidle');
	if (expectedAvailable === 't')
		await expect(page.getByTestId('available-checkbox')).toBeChecked();
	else await expect(page.getByTestId('available-checkbox')).not.toBeChecked();

	// Edit the status via the EditableText: click Edit, fill, then blur — the
	// field's onblur commits the edit (avoids racing a second toggle click, and
	// works for the textarea, which only commits on Cmd+Enter, not plain Enter).
	const status = `e2e status ${Date.now()}`;
	const statusToggle = page.getByTestId('status-toggle');
	await statusToggle.waitFor();
	await statusToggle.click();
	const statusField = page.getByTestId('status');
	await expect(statusField).toBeEditable();
	await statusField.fill(status);
	await statusField.blur();

	await expect
		.poll(() => sql(`select status from public.scholars where id = '${AUTHOR1_ID}';`))
		.toBe(status);

	// The status survives a reload.
	await page.reload();
	await page.waitForLoadState('networkidle');
	await expect(page.getByTestId('status')).toHaveValue(status);

	await logout(page);
});

/**
 * Shared body for the two scholar-to-scholar gift tests: author1 gifts two
 * Epistemology tokens to author2 (looked up by `recipient`, an ORCID or email),
 * then we verify the gift appears in author2's transaction history and that
 * author2's balance increased by two.
 */
async function giftToAuthor2(
	page: import('@playwright/test').Page,
	context: import('@playwright/test').BrowserContext,
	recipient: string,
	purpose: string
) {
	test.setTimeout(90_000);

	const balanceBefore = Number(
		sql(
			`select count(*) from public.tokens where scholar = '${AUTHOR2_ID}' and currency = '${CURRENCY_ID}';`
		)
	);

	await login(AUTHOR1_EMAIL, page, context);
	await page.goto(`/scholar/${AUTHOR1_ID}`);
	await page.waitForLoadState('networkidle');

	// Expand the gift card to reveal its form.
	const giftCard = page.getByTestId('scholar-gift-card');
	await giftCard.waitFor();
	await giftCard.click();
	await page.getByTestId('gift-recipient').fill(recipient);
	await page.getByTestId('gift-amount').fill('2');
	await page.getByTestId('gift-purpose').fill(purpose);
	await page.getByTestId('gift-consent').click();
	await page.getByTestId('gift-submit').click();

	// The transfer records an approved scholar→scholar transaction.
	await expect
		.poll(() =>
			Number(
				sql(
					`select count(*) from public.transactions where from_scholar = '${AUTHOR1_ID}' and to_scholar = '${AUTHOR2_ID}' and status = 'approved' and purpose = '${purpose}';`
				)
			)
		)
		.toBeGreaterThanOrEqual(1);

	// Cross-flow: the recipient sees the gift in their transaction history.
	await logout(page);
	await login(AUTHOR2_EMAIL, page, context);
	await page.goto(`/scholar/${AUTHOR2_ID}/transactions`);
	await page.waitForLoadState('networkidle');
	await expect(page.getByRole('cell', { name: purpose })).toBeVisible();

	// The recipient's balance reflects the gift.
	const balanceAfter = Number(
		sql(
			`select count(*) from public.tokens where scholar = '${AUTHOR2_ID}' and currency = '${CURRENCY_ID}';`
		)
	);
	expect(balanceAfter).toBe(balanceBefore + 2);

	await logout(page);
}

test('scholar gifts tokens to another scholar by ORCID', async ({ page, context }) => {
	await giftToAuthor2(page, context, AUTHOR2_ORCID, `e2e orcid gift ${Date.now()}`);
});

test('scholar gifts tokens to another scholar by email', async ({ page, context }) => {
	await giftToAuthor2(page, context, AUTHOR2_EMAIL, `e2e email gift ${Date.now()}`);
});
