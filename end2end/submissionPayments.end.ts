import { test, expect } from '@playwright/test';
import { logout } from '../src/routes/login';
import { loginAndGoto, SEED, sql } from './test-utils';

const PAGE = `/venue/${SEED.venuePath}/submissions/payments`;

test('an admin sees which manuscripts are unpaid and who to write to', async ({
	page,
	context
}) => {
	const stamp = Date.now();
	const owed = `PAY-OWED-${stamp}`;
	const imported = `PAY-IMPORTED-${stamp}`;
	const missing = `PAY-MISSING-${stamp}`;
	const paid = SEED.submissions.tok001.externalId;
	const type = sql(
		`select id from public.submission_types where venue = '${SEED.venue}' order by id limit 1;`
	);
	// author1 paid their charge; author2's is still waiting for their approval, which is
	// what a co-author's charge looks like until they act on it.
	const approved = sql(
		`insert into public.transactions (creator, from_scholar, to_venue, tokens, currency, purpose, status) values ('${SEED.scholars.author1.id}', '${SEED.scholars.author1.id}', '${SEED.venue}', array_fill('00000000-0000-0000-0000-000000000000'::uuid, array[1]), '${SEED.currency}', 'Payment for submission ${owed}', 'approved') returning id;`
	);
	const proposed = sql(
		`insert into public.transactions (creator, from_scholar, to_venue, tokens, currency, purpose, status) values ('${SEED.scholars.author1.id}', '${SEED.scholars.author2.id}', '${SEED.venue}', array_fill('00000000-0000-0000-0000-000000000000'::uuid, array[1]), '${SEED.currency}', 'Payment for submission ${owed}', 'proposed') returning id;`
	);
	sql(
		`insert into public.submissions (venue, externalid, submission_type, authors, payments, transactions, title) values ('${SEED.venue}', '${owed}', '${type}', array['${SEED.scholars.author1.id}', '${SEED.scholars.author2.id}']::uuid[], array[1, 1], array['${approved}', '${proposed}']::uuid[], 'Owed ${stamp}');`
	);
	sql(
		`insert into public.submissions (venue, externalid, submission_type, authors, payments, transactions, imported, title) values ('${SEED.venue}', '${imported}', '${type}', '{}', '{}', '{}', true, 'Imported ${stamp}');`
	);

	try {
		await loginAndGoto(page, context, SEED.scholars.editor.email, PAGE, 'payments-ids');
		// A spreadsheet column, with a repeat and a blank line.
		await page
			.getByTestId('payments-ids')
			.fill([paid, owed, '', imported, missing, paid].join('\n'));
		await page.getByTestId('payments-check').click();

		await expect(page.getByTestId('payments-summary')).toContainText(
			'Checked 4: 1 not submitted, 1 outstanding, 1 imported, 1 paid, 0 free.'
		);

		// Rows needing action first.
		const expected: [string, string][] = [
			[missing, 'not submitted'],
			[owed, 'outstanding'],
			[imported, 'imported'],
			[paid, 'paid']
		];
		for (const [index, [id, status]] of expected.entries()) {
			await expect(page.getByTestId(`payments-row-${index}-id`)).toHaveText(id);
			await expect(page.getByTestId(`payments-row-${index}-status`)).toHaveText(status);
		}

		// Only the co-author who hasn't paid is named, with their address.
		const contact = page.getByTestId('payments-row-1-contact');
		await expect(contact).toContainText(SEED.scholars.author2.name);
		await expect(contact).toContainText(SEED.scholars.author2.email);
		await expect(contact).toContainText("hasn't approved their charge");
		await expect(contact).not.toContainText(SEED.scholars.author1.name);

		// Copy emails gathers the addresses to write to, and only those.
		await context.grantPermissions(['clipboard-read', 'clipboard-write']);
		await page.getByTestId('payments-copy-emails').click();
		await expect(page.getByTestId('payments-copy-emails')).toContainText('Copied');
		expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(
			SEED.scholars.author2.email
		);

		await logout(page);
	} finally {
		sql(`delete from public.submissions where externalid in ('${owed}', '${imported}');`);
		sql(`delete from public.transactions where id in ('${approved}', '${proposed}');`);
	}
});

test('a non-admin is told only admins can check payments', async ({ page, context }) => {
	await loginAndGoto(page, context, SEED.scholars.author1.email, PAGE, 'payments-not-admin');
	await expect(page.getByTestId('payments-ids')).toHaveCount(0);
	await logout(page);
});
