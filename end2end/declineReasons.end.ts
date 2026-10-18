import { expect, test } from '@playwright/test';
import { login } from '../src/routes/login';
import { SEED, sql } from './test-utils';

const VENUE_ID = SEED.venue;
const VENUE_PATH = SEED.venuePath;
const EDITOR_EMAIL = SEED.scholars.editor.email;

const reasons = () =>
	sql(
		`select string_agg(text, '|' order by rank) from public.decline_reasons where venueid = '${VENUE_ID}';`
	);

/** Put the venue's reasons back as the seed's trigger made them, for whatever runs next. */
let original = '';
test.beforeAll(() => {
	original = sql(
		`select string_agg(format('(%L, %L, %s)', venueid, text, rank), ', ' order by rank) from public.decline_reasons where venueid = '${VENUE_ID}';`
	);
});
test.afterAll(() => {
	sql(`delete from public.decline_reasons where venueid = '${VENUE_ID}';`);
	if (original !== '')
		sql(`insert into public.decline_reasons (venueid, text, rank) values ${original};`);
});

test('editor edits, adds, reorders, and deletes decline reasons', async ({ page, context }) => {
	await login(EDITOR_EMAIL, page, context);
	await page.goto(`/venue/${VENUE_PATH}/settings`);
	await page.waitForLoadState('networkidle');

	// The venue starts with the defaults.
	await expect(page.getByTestId('decline-reasons').getByRole('listitem')).toHaveCount(5);

	// Edit the first.
	await page.getByTestId('decline-reason-text-0-toggle').click();
	const field = page.getByTestId('decline-reason-text-0');
	await field.fill('We needed someone with other expertise.');
	// A multi-line field, so Enter is a newline; the toggle saves.
	await page.getByTestId('decline-reason-text-0-toggle').click();
	await expect
		.poll(() =>
			sql(`select text from public.decline_reasons where venueid = '${VENUE_ID}' and rank = 0;`)
		)
		.toBe('We needed someone with other expertise.');

	// Add one at the end.
	await page.getByTestId('new-decline-reason').fill('We are not seating new reviewers this month.');
	await page.getByTestId('add-decline-reason').click();
	await expect.poll(reasons).toMatch(/\|We are not seating new reviewers this month\.$/);

	// Move it up one.
	await page.getByTestId('decline-reason-up-5').click();
	await expect
		.poll(reasons)
		.toMatch(
			/\|We are not seating new reviewers this month\.\|We wanted to avoid a possible conflict of interest\.$/
		);

	// Delete it, confirming, once the list shows the new order.
	await expect(page.getByTestId('decline-reason-4')).toContainText('not seating new reviewers');
	await page.getByTestId('decline-reason-delete-4').click();
	await page.getByTestId('decline-reason-delete-4').click();
	await expect.poll(reasons).not.toContain('not seating new reviewers');
});
