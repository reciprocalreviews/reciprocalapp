import { expect, test } from '@playwright/test';
import { execSync } from 'child_process';
import { login } from '../src/routes/login';

const VENUE_ID = 'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6';
const CURRENCY_ID = 'c60c9fca-ad37-11f0-a9a1-57b72e1e85ac';
const MINTER_EMAIL = 'r1@uni.edu';
const EDITOR_ID = 'd181d165-8b6a-4d79-ad28-a9aece21d813';
const EDITOR_EMAIL = 'editor@uni.edu';
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

test('an editor approves a pending venue transfer; status moves to approved and tokens transfer', async ({
	page,
	context
}) => {
	// Seed a proposed venue→scholar transfer. Venue reserve payouts are spent
	// and approved by the venue's editors/admins (DESIGN.md L107/L390); currency
	// minters only mint and approve mints, and may not move token ownership
	// (supabase/schemas/tokens.sql), so the editor performs the approval here.
	const recipientID = sql(`select id from public.scholars where email = '${RECIPIENT_EMAIL}';`);
	const recipientBalanceBefore = Number(
		sql(
			`select count(*) from public.tokens where scholar = '${recipientID}' and currency = '${CURRENCY_ID}';`
		)
	);

	// Seed three real tokens into the venue reserve and reference them directly,
	// so approval is a pure transfer of existing reserve tokens. (Approving a
	// placeholder-token transfer would force a mint, which is a minter-only
	// action — and minting into a venue you administer is self-dealing.)
	const reserveTokenIds = sql(
		`insert into public.tokens (currency, venue) values ('${CURRENCY_ID}','${VENUE_ID}'),('${CURRENCY_ID}','${VENUE_ID}'),('${CURRENCY_ID}','${VENUE_ID}') returning id;`
	)
		.split('\n')
		.map((s) => s.trim())
		.filter(Boolean);
	const tokensLiteral = `array[${reserveTokenIds.map((id) => `'${id}'`).join(',')}]::uuid[]`;

	const purpose = `e2e approve test ${Date.now()}`;
	const txnID = sql(
		`insert into public.transactions (creator, from_scholar, from_venue, to_scholar, to_venue, tokens, currency, purpose, status) values ('${EDITOR_ID}', null, '${VENUE_ID}', '${recipientID}', null, ${tokensLiteral}, '${CURRENCY_ID}', '${purpose}', 'proposed') returning id;`
	);
	expect(txnID).toMatch(/^[0-9a-f-]+$/);

	await login(EDITOR_EMAIL, page, context);
	await page.goto(`/venue/${VENUE_ID}/transactions`);
	await page.waitForLoadState('networkidle');

	// Find the row for the new proposed transaction. Match the table cell
	// by accessible name (Playwright's getByText also matches the hidden
	// TextField rulers used by the decline-reason input on each row).
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

test('minter cannot approve a venue→minter transaction (anti-self-dealing UPDATE)', async ({
	page,
	context
}) => {
	// DESIGN.md L388: a minter must not approve transactions in which they
	// are the recipient. Seed a proposed venue→minter row and verify (1) the
	// UI hides the approve button when the recipient views it and (2) the RLS
	// UPDATE policy refuses to flip the status when the minter tries directly.
	const minterID = sql(`select id from public.scholars where email = '${MINTER_EMAIL}';`);

	const purpose = `e2e self-deal update test ${Date.now()}`;
	const txnID = sql(
		`insert into public.transactions (creator, from_scholar, from_venue, to_scholar, to_venue, tokens, currency, purpose, status) values ('${EDITOR_ID}', null, '${VENUE_ID}', '${minterID}', null, array_fill('00000000-0000-0000-0000-000000000000'::uuid, array[1]), '${CURRENCY_ID}', '${purpose}', 'proposed') returning id;`
	);
	expect(txnID).toMatch(/^[0-9a-f-]+$/);

	await login(MINTER_EMAIL, page, context);
	await page.goto(`/venue/${VENUE_ID}/transactions`);
	await page.waitForLoadState('networkidle');

	// The row is visible (minter can SELECT transactions for their currency)…
	await expect(page.getByRole('cell', { name: purpose })).toBeVisible();
	// …but the approve button is not rendered for the recipient.
	const approveButton = page.locator(
		`tr:has(td:has-text(${JSON.stringify(purpose)})) [data-testid$="-approve"]`
	);
	await expect(approveButton).toHaveCount(0);

	// Bypass the UI and attempt the UPDATE under the minter's auth context.
	// The with-check on the RLS policy either raises or silently rejects;
	// either way the row stays 'proposed'.
	try {
		sql(
			`begin; set local role authenticated; set local request.jwt.claims to '{"sub":"${minterID}","role":"authenticated"}'; update public.transactions set status = 'approved' where id = '${txnID}'; commit;`
		);
	} catch {
		// Expected: RLS with-check raises and the transaction rolls back.
	}
	expect(sql(`select status from public.transactions where id = '${txnID}';`)).toBe('proposed');
});

test('minter declining a proposed transaction emails the proposer and records the decliner', async ({
	page,
	context
}) => {
	// Set up: the editor proposes a venue → author2 transaction. The minter
	// (r1) declines it, which should:
	//   1. flip status to 'declined', preserving the original purpose
	//   2. record decliner = r1 and decline_reason = the typed text
	//   3. queue a TransactionDeclinedVenue email row addressed to the editor
	const recipientID = sql(`select id from public.scholars where email = '${RECIPIENT_EMAIL}';`);
	const minterID = sql(`select id from public.scholars where email = '${MINTER_EMAIL}';`);

	// Clear any prior decline emails to the editor so the count assertion is
	// deterministic across re-runs.
	sql(
		`delete from public.emails where event in ('TransactionDeclined','TransactionDeclinedVenue') and scholar = '${EDITOR_ID}';`
	);

	const purpose = `e2e decline test ${Date.now()}`;
	const reason = 'Insufficient justification';
	const txnID = sql(
		`insert into public.transactions (creator, from_scholar, from_venue, to_scholar, to_venue, tokens, currency, purpose, status) values ('${EDITOR_ID}', null, '${VENUE_ID}', '${recipientID}', null, array_fill('00000000-0000-0000-0000-000000000000'::uuid, array[2]), '${CURRENCY_ID}', '${purpose}', 'proposed') returning id;`
	);
	expect(txnID).toMatch(/^[0-9a-f-]+$/);

	await login(MINTER_EMAIL, page, context);
	await page.goto(`/venue/${VENUE_ID}/transactions`);
	await page.waitForLoadState('networkidle');

	// Open the decline dialog on our row, fill the reason, confirm. Each row
	// owns its own Dialog state, so scoping all three actions to this row's
	// <tr> targets the right dialog. The decline-confirm is itself a confirm
	// button (warn pattern) — first click enters confirm mode, second commits.
	const row = page.locator(`tr:has(td:has-text(${JSON.stringify(purpose)}))`);
	await row.locator('[data-testid$="-decline-initiate"]').click();
	await row.locator('[data-testid$="-decline-reason"]').fill(reason);
	await row.locator('[data-testid$="-decline-confirm"]').click();
	await row.locator('[data-testid$="-decline-confirm"]').click();

	// Audit columns reflect who declined and why; purpose is untouched.
	await expect
		.poll(() =>
			sql(
				`select status || '|' || coalesce(decliner::text,'') || '|' || coalesce(decline_reason,'') || '|' || purpose from public.transactions where id = '${txnID}';`
			)
		)
		.toBe(`declined|${minterID}|${reason}|${purpose}`);

	// Exactly one decline email queued for the editor (the proposer).
	await expect
		.poll(() =>
			Number(
				sql(
					`select count(*) from public.emails where event in ('TransactionDeclined','TransactionDeclinedVenue') and scholar = '${EDITOR_ID}';`
				)
			)
		)
		.toBe(1);

	// Sanity: subject says "declined" and the body mentions the reason and the
	// decliner's name (so the proposer can follow up).
	const minterName = sql(`select name from public.scholars where id = '${minterID}';`);
	const emailContent = sql(
		`select subject || '||' || message from public.emails where event in ('TransactionDeclined','TransactionDeclinedVenue') and scholar = '${EDITOR_ID}' order by time_sent desc limit 1;`
	);
	expect(emailContent.toLowerCase()).toContain('declined');
	expect(emailContent).toContain(reason);
	expect(emailContent).toContain(minterName);
});

test('editor cannot insert an already-approved venue→editor transaction (anti-self-dealing INSERT)', async () => {
	// Gift flow: a venue admin inserts a status='approved' transaction
	// directly (see Gift.svelte). The new INSERT-side check must reject the
	// case where the editor names themselves as recipient.
	const purpose = `e2e self-deal insert test ${Date.now()}`;
	try {
		sql(
			`begin; set local role authenticated; set local request.jwt.claims to '{"sub":"${EDITOR_ID}","role":"authenticated"}'; insert into public.transactions (creator, from_scholar, from_venue, to_scholar, to_venue, tokens, currency, purpose, status) values ('${EDITOR_ID}', null, '${VENUE_ID}', '${EDITOR_ID}', null, array_fill('00000000-0000-0000-0000-000000000000'::uuid, array[1]), '${CURRENCY_ID}', '${purpose}', 'approved'); commit;`
		);
	} catch {
		// Expected: RLS check raises and the transaction rolls back.
	}
	expect(sql(`select count(*) from public.transactions where purpose = '${purpose}';`)).toBe('0');
});
