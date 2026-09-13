import { expect, test } from '@playwright/test';
import { login, logout } from '../src/routes/login';
import { SEED, sql } from './test-utils';

/**
 * Requesting compensation from the venue page.
 *
 * The form had no coverage at all, which is how it kept three defects at once: it announced
 * success through its own `addFeedback` rather than `handle()`, so the confirmation appeared
 * alongside the per-recipient banners saying the same thing; it did that from a `.then()`, and
 * `handle()` RESOLVES false on failure rather than rejecting, so a failed request was announced
 * as a success and had its three fields cleared with it; and the confirmation was an English
 * literal in the component.
 */

const VENUE_PATH = SEED.venuePath;
const VOLUNTEER = SEED.scholars.r1; // an accepted Reviewer with an approved assignment
/** The seed submission's ID in the venue's own reviewing system, which is what this form asks
 * for — not RR's own id. */
const MANUSCRIPT = 'TOK-2025-001';

test('a request reports who was told, not a second generic confirmation', async ({
	page,
	context
}) => {
	sql(`delete from public.emails where event = 'CompensationRequested';`);
	try {
		await login(VOLUNTEER.email, page, context);
		await page.goto(`/venue/${VENUE_PATH}`);
		await page.waitForLoadState('networkidle');

		await page.getByTestId('compensation-manuscript').fill(MANUSCRIPT);
		await page.getByTestId('compensation-role').selectOption({ label: 'Reviewer' });
		await page.getByTestId('compensation-note').fill('I reviewed this in March.');
		await page.getByTestId('request-compensation').click();

		const banners = page.getByTestId('feedback-success');
		await expect(banners.first()).toBeVisible({ timeout: 10_000 });

		// Wait for the CLEARED FIELDS before counting banners. This is an assertion about an
		// absence, and the extra banner used to arrive late — handle() resolves only after
		// awaiting invalidateAll(), so the old `.then()` ran a refetch later, and a count taken
		// when the first banner appeared passed whether or not the bug was there. The cleared
		// field is the deterministic end of the action under both versions: the old code
		// emptied the three fields and posted its line in one synchronous block, so once this
		// is empty any second banner has already been added.
		await expect(page.getByTestId('compensation-manuscript')).toHaveValue('');
		await expect(page.getByTestId('compensation-note')).toHaveValue('');

		// Somebody was emailed, so the banners name them. The generic line is suppressed —
		// it used to appear as well, which was the same news twice and the less useful telling.
		await expect(banners).toHaveCount(1);
		await expect(banners.first()).toContainText('was emailed');
		expect((await banners.allInnerTexts()).join(' | ')).not.toContain('Compensation request sent.');
	} finally {
		sql(`delete from public.emails where event = 'CompensationRequested';`);
	}
	await logout(page);
});

test('a failed request neither claims success nor discards what was typed', async ({
	page,
	context
}) => {
	// A manuscript ID the venue has never heard of, which is the ordinary way this fails: a
	// reviewer mistypes the ID their reviewing system gave them. requestCompensation stops at
	// CompensationSubmissionNotFound before writing anything, so there is nothing to clean up.
	const unknown = `TOK-NOPE-${Date.now()}`;
	await login(VOLUNTEER.email, page, context);
	await page.goto(`/venue/${VENUE_PATH}`);
	await page.waitForLoadState('networkidle');

	await page.getByTestId('compensation-manuscript').fill(unknown);
	await page.getByTestId('compensation-role').selectOption({ label: 'Reviewer' });
	await page.getByTestId('compensation-note').fill('Please pay me.');
	await page.getByTestId('request-compensation').click();

	await expect(page.getByTestId('feedback-error').first()).toBeVisible({ timeout: 10_000 });
	// No success banner at all. The old chain posted one regardless of the outcome, so a
	// mistyped ID was reported as a request that had gone out.
	await expect(page.getByTestId('feedback-success')).toHaveCount(0);
	// And the typing survives, so the ID can be corrected rather than retyped from scratch.
	await expect(page.getByTestId('compensation-manuscript')).toHaveValue(unknown);
	await expect(page.getByTestId('compensation-note')).toHaveValue('Please pay me.');

	await logout(page);
});
