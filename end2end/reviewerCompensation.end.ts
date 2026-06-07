import { expect, test } from '@playwright/test';
import { login } from '../src/routes/login';
import { SEED, sql } from './test-utils';

const VENUE_ID = SEED.venue;
const CURRENCY_ID = SEED.currency;
const SUBMISSION_ID = SEED.submissions.tok001;
const REVIEWER_ROLE_ID = SEED.roles.reviewer;

test('AE compensates a reviewer and tokens transfer immediately', async ({ page, context }) => {
	await login('ae@uni.edu', page, context);

	await page.goto(`/venue/${VENUE_ID}/submission/${SUBMISSION_ID}`);
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
	// Drain the venue's reserve so the next Complete click is forced down the
	// insufficient-funds branch of the complete_assignment RPC. Done via SQL
	// because there's no UI affordance for "remove every venue token."
	sql(`delete from public.tokens where venue = '${VENUE_ID}';`);

	// Also undo any prior-test completion of r1's assignment so this test has
	// an approved-but-incomplete row to click on.
	sql(
		`update public.assignments set completed = false where submission = '${SUBMISSION_ID}' and completed = true;`
	);

	await login('ae@uni.edu', page, context);
	await page.goto(`/venue/${VENUE_ID}/submission/${SUBMISSION_ID}`);
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

	// Restore venue tokens so subsequent tests in the suite (e.g., the venue
	// gift test) see a non-empty reserve. This intentionally mirrors the seed
	// quantity (50) rather than tracking an exact pre-test count, since the
	// happy-path test above already consumed some.
	sql(
		`insert into public.tokens (currency, scholar, venue) select '${CURRENCY_ID}', null, '${VENUE_ID}' from generate_series(1, 50);`
	);
});
