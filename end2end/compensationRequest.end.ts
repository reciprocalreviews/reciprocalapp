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
const MANUSCRIPT = SEED.submissions.tok001.externalId;

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
		// Two people: the venue's admin and the associate editor who approves reviewers on
		// this submission. The recipients are worked out by request_compensation now; the
		// client used to read them from assignments the reviewer cannot see, and so only
		// ever found the admin.
		await expect(banners).toHaveCount(2);
		for (const text of await banners.allInnerTexts()) expect(text).toContain('was emailed');
		expect((await banners.allInnerTexts()).join(' | ')).not.toContain('Compensation request sent.');

		// A request is about this venue, so a reply to it belongs with the venue, not the
		// stewards: it carries the venue and that venue's admin as its Reply-To.
		expect(
			sql(
				`select count(*) from public.emails where event = 'CompensationRequested' and (venue is null or reply_to is null or reply_to is distinct from public.venue_reply_to(venue));`
			)
		).toBe('0');
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

test('a reviewer claims work on a submission nobody seated them on, and an admin answers it', async ({
	page,
	context
}) => {
	// A backlog submission imported before its editor joined: nobody on the platform could
	// have seated the reviewer on it, and they cannot see it. The request still has to land.
	const manuscript = `TOK-CLAIM-${Date.now()}`;
	const submission = sql(
		`insert into public.submissions (venue, externalid, authors, payments, transactions, title, submission_type, imported) select '${SEED.venue}', '${manuscript}', '{}', '{}', '{}', 'An unseated backlog paper', submission_type, true from public.submissions where id = '${SEED.submissions.tok001.id}' returning id;`
	);
	const REASON = 'There is no review from you on record for this manuscript.';
	const claimState = () =>
		sql(
			`select approved::text || '|' || coalesce(decline_reason, '') from public.assignments where submission = '${submission}' and scholar = '${VOLUNTEER.id}';`
		);

	try {
		await login(VOLUNTEER.email, page, context);
		await page.goto(`/venue/${VENUE_PATH}`);
		await page.waitForLoadState('networkidle');
		await page.getByTestId('compensation-manuscript').fill(manuscript);
		await page.getByTestId('compensation-role').selectOption({ label: 'Reviewer' });
		await page.getByTestId('request-compensation').click();
		await expect(page.getByTestId('compensation-manuscript')).toHaveValue('');
		await expect.poll(claimState).toBe('false|');
		await logout(page);

		// The venue's admin is the only approver while nobody edits the paper.
		await login(SEED.scholars.editor.email, page, context);
		await page.goto(`/venue/${VENUE_PATH}/submission/${submission}`);
		await page.waitForLoadState('networkidle');
		await expect(page.getByTestId('claim')).toBeVisible();
		await expect(page.getByTestId('pay-claim')).toBeVisible();

		await page.getByTestId('decline-bid').click();
		await page.getByTestId('decline-bid-reason').fill(REASON);
		await page.getByTestId('decline-bid-confirm').click();
		await expect.poll(claimState).toBe(`false|${REASON}`);
		await expect
			.poll(() =>
				sql(
					`select count(*) from public.emails where event = 'ClaimDeclined' and scholar = '${VOLUNTEER.id}';`
				)
			)
			.toBe('1');
	} finally {
		sql(`delete from public.submissions where id = '${submission}';`);
		sql(
			`delete from public.emails where event in ('CompensationRequested', 'ClaimDeclined') and args->>1 = '${submission}' or (event = 'ClaimDeclined' and scholar = '${VOLUNTEER.id}');`
		);
	}
	await logout(page);
});
