import { expect, test } from '@playwright/test';
import { execSync } from 'child_process';
import { login } from '../src/routes/login';

const VENUE_ID = 'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6';
const CURRENCY_ID = 'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac';
const MINTER_EMAIL = 'r1@uni.edu';
const EDITOR_ID = 'd181d165-8b6a-4d79-ad28-a9aece21d813';
const RECIPIENT_EMAIL = 'author2@uni.edu';

function sql(statement: string): string {
	// `-q` suppresses the trailing command tag (e.g. "INSERT 0 1") so callers
	// using statements with RETURNING get back only the value.
	return execSync(
		`docker exec supabase_db_reciprocalapp psql -U postgres -d postgres -t -A -q -c ${JSON.stringify(statement)}`,
		{ encoding: 'utf-8' }
	).trim();
}

test('minter mints new tokens; the venue reserve increases', async ({ page, context }) => {
	await login(MINTER_EMAIL, page, context);

	const reserveBefore = Number(
		sql(
			`select count(*) from public.tokens where venue = '${VENUE_ID}' and currency = '${CURRENCY_ID}';`
		)
	);

	await page.goto(`/currency/${CURRENCY_ID}`);
	await page.waitForLoadState('networkidle');

	// Expand the mint card to reveal its form.
	await page.getByTestId('mint-card').click();

	await page.getByTestId('mint-amount').fill('5');
	await page.getByTestId('mint-purpose').fill('e2e mint test');
	await page.getByTestId('mint-consent').click();
	await page.getByTestId('mint-submit').click();

	// The minted tokens should land in the venue's reserve.
	await expect
		.poll(() =>
			Number(
				sql(
					`select count(*) from public.tokens where venue = '${VENUE_ID}' and currency = '${CURRENCY_ID}';`
				)
			)
		)
		.toBe(reserveBefore + 5);

	// The mint is recorded as an approved transaction (from_null → to_venue).
	const mintTxnCount = Number(
		sql(
			`select count(*) from public.transactions where to_venue = '${VENUE_ID}' and from_venue is null and from_scholar is null and status = 'approved' and purpose = 'e2e mint test';`
		)
	);
	expect(mintTxnCount).toBeGreaterThanOrEqual(1);
});

test('minter approves a pending transaction; status moves to approved and tokens transfer', async ({
	page,
	context
}) => {
	// Seed a proposed venue→scholar transaction created by the EDITOR (not
	// the minter), so the minter is a third party performing the approval.
	const recipientID = sql(`select id from public.scholars where email = '${RECIPIENT_EMAIL}';`);
	const recipientBalanceBefore = Number(
		sql(
			`select count(*) from public.tokens where scholar = '${recipientID}' and currency = '${CURRENCY_ID}';`
		)
	);

	const purpose = `e2e approve test ${Date.now()}`;
	const txnID = sql(
		`insert into public.transactions (creator, from_scholar, from_venue, to_scholar, to_venue, tokens, currency, purpose, status) values ('${EDITOR_ID}', null, '${VENUE_ID}', '${recipientID}', null, array_fill('00000000-0000-0000-0000-000000000000'::uuid, array[3]), '${CURRENCY_ID}', '${purpose}', 'proposed') returning id;`
	);
	expect(txnID).toMatch(/^[0-9a-f-]+$/);

	await login(MINTER_EMAIL, page, context);
	await page.goto(`/venue/${VENUE_ID}/transactions`);
	await page.waitForLoadState('networkidle');

	// Find the row for the new proposed transaction. Match the table cell
	// by accessible name (Playwright's getByText also matches the hidden
	// TextField rulers used by the cancel-reason input on each row).
	await expect(page.getByRole('cell', { name: purpose })).toBeVisible();

	// Click the approve button on whichever row index hosts our purpose.
	const approveButton = page
		.locator(`tr:has(td:has-text(${JSON.stringify(purpose)})) [data-testid$="-approve"]`)
		.first();
	await approveButton.click();

	// The transaction's status flips to 'approved'.
	await expect
		.poll(() => sql(`select status from public.transactions where id = '${txnID}';`))
		.toBe('approved');

	// Tokens were transferred to the recipient.
	await expect
		.poll(() =>
			Number(
				sql(
					`select count(*) from public.tokens where scholar = '${recipientID}' and currency = '${CURRENCY_ID}';`
				)
			)
		)
		.toBe(recipientBalanceBefore + 3);
});

test('a gift transaction is visible in venue transactions, scholar history, and balance', async ({
	page,
	context
}) => {
	// Editor gifts tokens from venue → scholar via the Gift UI on the venue
	// transactions page; verify the same transaction surfaces in three
	// distinct views and that the recipient's balance reflects the change.
	const recipientID = sql(`select id from public.scholars where email = '${RECIPIENT_EMAIL}';`);
	const balanceBefore = Number(
		sql(
			`select count(*) from public.tokens where scholar = '${recipientID}' and currency = '${CURRENCY_ID}';`
		)
	);

	const purpose = `e2e visibility test ${Date.now()}`;

	await login('editor@uni.edu', page, context);
	await page.goto(`/venue/${VENUE_ID}/transactions`);
	await page.waitForLoadState('networkidle');

	await page.getByTestId('venue-gift-card').click();
	await page.getByTestId('gift-recipient').fill(RECIPIENT_EMAIL);
	await page.getByTestId('gift-amount').fill('2');
	await page.getByTestId('gift-purpose').fill(purpose);
	await page.getByTestId('gift-consent').click();
	await page.getByTestId('gift-submit').click();

	// (1) The gift is visible on the venue transactions page (still editor).
	await expect(page.getByRole('cell', { name: purpose })).toBeVisible({ timeout: 10_000 });

	// (2) The recipient's transaction history shows the same transaction. Log
	// in as the recipient.
	await context.clearCookies();
	await login(RECIPIENT_EMAIL, page, context);
	await page.goto(`/scholar/${recipientID}/transactions`);
	await page.waitForLoadState('networkidle');
	await expect(page.getByRole('cell', { name: purpose })).toBeVisible();

	// (3) The recipient's balance reflects the gift.
	const balanceAfter = Number(
		sql(
			`select count(*) from public.tokens where scholar = '${recipientID}' and currency = '${CURRENCY_ID}';`
		)
	);
	expect(balanceAfter).toBe(balanceBefore + 2);
});
