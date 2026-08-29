import { expect, test } from '@playwright/test';
import { login } from '../src/routes/login';
import { asScholar, SEED, sql } from './test-utils';

const VENUE_ID = SEED.venue;
const VENUE_PATH = SEED.venuePath;
const CURRENCY_ID = SEED.currency;
const SUBMISSION_ID = SEED.submissions.tok001;
const REVIEWER_ROLE_ID = SEED.roles.reviewer;
// Only a venue's admins or a priority-0 role holder may move its reserve, and the
// mover may not be the recipient (transfer_tokens, supabase/schemas/transactions.sql).
// The AE who drives the UI below is neither, so the editor parks the reserve.
const EDITOR = SEED.scholars.editor;
// Somewhere to park it. r3 holds no tokens in the seed and no test asserts a
// balance for them, so the round trip is invisible to the rest of the suite.
const PARK = SEED.scholars.r3;

test('AE compensates a reviewer and tokens transfer immediately', async ({ page, context }) => {
	await login('ae@uni.edu', page, context);

	await page.goto(`/venue/${VENUE_PATH}/submission/${SUBMISSION_ID}`);
	await page.waitForLoadState('networkidle');

	// At least one approved-but-incomplete Reviewer assignment is present
	// (r1, Rigor Russ in the seed; possibly more after reviewerAssignment.end.ts
	// approves additional bids). Click the first one — the RPC behavior is
	// identical regardless of which assignment we target.
	const completeButton = page.getByTestId('complete-assignment').first();
	await expect(completeButton).toBeVisible();

	// First click flips the button into confirm mode; second click runs the
	// transfer via the complete_assignment RPC. The Button component forwards
	// the same testid to its confirm-stage button.
	await completeButton.click();
	await page.getByTestId('complete-assignment').first().click();

	// A success feedback banner confirms the transfer succeeded and the
	// scholar was notified.
	await expect(page.getByTestId('feedback-success').first()).toBeVisible({ timeout: 10_000 });

	// At least one row in the table now shows the Completed status.
	await expect(page.getByTestId('assignment-completed').first()).toBeVisible();
});

test('when the venue is out of tokens, Complete surfaces an error and queues a proposed mint', async ({
	page,
	context
}) => {
	// Empty the venue's reserve so the next Complete click is forced down the
	// insufficient-funds branch of the complete_assignment RPC. The tokens are
	// moved, not deleted: a raw `delete from public.tokens` logs a burn event for
	// every row, and those tokens then replay as owned by nobody, which is what
	// left the pgTAP invariants failing after every local `npm test` (#152).
	const reserve = Number(
		sql(
			`select count(*) from public.tokens where venue = '${VENUE_ID}' and currency = '${CURRENCY_ID}';`
		)
	);
	if (reserve > 0)
		asScholar(
			EDITOR.id,
			`select public.transfer_tokens('${CURRENCY_ID}', '${VENUE_ID}', 'venueid', '${PARK.id}', 'scholarid', ${reserve}, 'e2e: park the venue reserve', null)`
		);

	try {
		// Also undo any prior-test completion of r1's assignment so this test has
		// an approved-but-incomplete row to click on.
		sql(
			`update public.assignments set completed = false where submission = '${SUBMISSION_ID}' and completed = true;`
		);

		await login('ae@uni.edu', page, context);
		await page.goto(`/venue/${VENUE_PATH}/submission/${SUBMISSION_ID}`);
		await page.waitForLoadState('networkidle');

		await page.getByTestId('complete-assignment').first().click();
		await page.getByTestId('complete-assignment').first().click();

		// An error feedback banner should appear telling the user a mint was
		// proposed and the minter was notified.
		await expect(page.getByTestId('feedback-error').first()).toBeVisible({ timeout: 10_000 });

		// The RPC should have inserted a proposed mint transaction (from=null,
		// to_venue=the venue, status=proposed) sized at the shortfall.
		const proposedMintCount = sql(
			`select count(*) from public.transactions where to_venue = '${VENUE_ID}' and from_venue is null and from_scholar is null and status = 'proposed';`
		);
		expect(Number(proposedMintCount)).toBeGreaterThanOrEqual(1);

		// The assignment must NOT have been marked completed.
		const stillIncomplete = sql(
			`select count(*) from public.assignments where submission = '${SUBMISSION_ID}' and role = '${REVIEWER_ROLE_ID}' and approved and not completed;`
		);
		expect(Number(stillIncomplete)).toBeGreaterThanOrEqual(1);
	} finally {
		// Hand the reserve back, exactly as much as we took, so later tests (e.g.
		// the venue gift test) see the balance they would have seen without us.
		// Spending one's own balance needs no venue authorization, so this runs as
		// the parking scholar rather than the editor. In a `finally` because a
		// failed assertion above must not leave the venue broke for everyone after.
		if (reserve > 0)
			asScholar(
				PARK.id,
				`select public.transfer_tokens('${CURRENCY_ID}', '${PARK.id}', 'scholarid', '${VENUE_ID}', 'venueid', ${reserve}, 'e2e: restore the venue reserve', null)`
			);
	}
});
