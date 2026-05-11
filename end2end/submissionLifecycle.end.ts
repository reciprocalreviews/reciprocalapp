import { execSync } from 'child_process';
import { expect, test } from '@playwright/test';
import { login } from '../src/routes/login';

const VENUE_ID = 'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6';
const SUBMISSION_ID = 'c61a1f5a-ad3a-11f0-9805-3f4d2f5e3c12'; // TOK-2025-001
const EDITOR_EMAIL = 'editor@uni.edu';
const EDITOR_ID = 'd181d165-8b6a-4d79-ad28-a9aece21d813';
const AUTHOR_EMAIL = 'author1@uni.edu'; // author of TOK-2025-001
const CONFLICT_DECLARER_EMAIL = 'r3@uni.edu'; // Reviewer volunteer with no assignments
const ASSIGNED_REVIEWER_NAME = 'Rigor Russ'; // r1, the approved Reviewer on TOK-2025-001
const REVIEWER_ROLE_ID = 'f3209eee-ad37-11f0-a9a2-7ba7c65d0a81';

function sql(statement: string): string {
	return execSync(
		`docker exec supabase_db_reciprocalapp psql -U postgres -d postgres -t -A -q -c ${JSON.stringify(statement)}`,
		{ encoding: 'utf-8' }
	).trim();
}

test('editor manually adds a single submission with themselves as the sole author', async ({
	page,
	context
}) => {
	// Get the editor's actual ORCID from the DB so the form's blur-based
	// scholar lookup resolves to the editor's scholar record.
	const editorOrcid = sql(`select orcid from public.scholars where id = '${EDITOR_ID}';`);

	const externalID = `EDITOR-ADD-${Date.now()}`;

	await login(EDITOR_EMAIL, page, context);
	await page.goto(`/venue/${VENUE_ID}/submissions/new`);
	await page.waitForLoadState('networkidle');

	await page.getByTestId('submission-title').fill('Editor-authored single submission');
	await page.getByTestId('submission-manuscript-id').fill(externalID);

	await page.getByTestId('author-orcid-0').fill(editorOrcid);
	await page.getByTestId('author-orcid-0').blur();
	await expect(page.getByTestId('scholar-found-0')).toBeVisible();

	// Pay the venue's full submission cost (10) as the sole author.
	await page.getByTestId('payment-slider-0').fill('10');

	await page.getByTestId('check-balances').click();
	await expect(
		page.locator('text=The authors have sufficient tokens to pay for this submission.')
	).toBeVisible();

	await page.getByTestId('submit-submission').click();
	await page.waitForURL(/\/venue\/.+\/submission\/.+/, { timeout: 60_000 });

	// The submission lands in the DB with the editor as sole author.
	const row = sql(
		`select cardinality(authors), authors[1] from public.submissions where externalid = '${externalID}';`
	);
	expect(row).toBe(`1|${EDITOR_ID}`);
});

test('scholar declares a conflict on a submission and it disappears from their submissions list', async ({
	page,
	context
}) => {
	const declarerID = sql(
		`select id from public.scholars where email = '${CONFLICT_DECLARER_EMAIL}';`
	);
	// Reset state: clear prior conflicts and put TOK-2025-001's Reviewer bids
	// back to bid-not-approved so the submission is visible in the bidding
	// list (reviewerAssignment.end.ts may have approved them earlier in the
	// shared-DB suite, which would hide the submission from new bidders).
	sql(
		`delete from public.conflicts where scholarid = '${declarerID}' and submissionid = '${SUBMISSION_ID}';`
	);
	sql(
		`update public.assignments set approved = false, bid = true where submission = '${SUBMISSION_ID}' and role = '${REVIEWER_ROLE_ID}' and scholar in (select id from public.scholars where email in ('r4@uni.edu', 'r5@uni.edu'));`
	);

	await login(CONFLICT_DECLARER_EMAIL, page, context);
	await page.goto(`/venue/${VENUE_ID}/submissions`);
	await page.waitForLoadState('networkidle');

	// TOK-2025-001 should be in the list with a declare-conflict button.
	await expect(page.locator('text=TOK-2025-001')).toBeVisible();
	const declareButtons = page.getByTestId('declare-conflict');
	const initialButtonCount = await declareButtons.count();
	expect(initialButtonCount).toBeGreaterThanOrEqual(1);

	// Click the declare-conflict button on the row containing TOK-2025-001.
	await page
		.locator('tr', { hasText: 'TOK-2025-001' })
		.getByTestId('declare-conflict')
		.click();

	// Conflict row landed in the DB.
	await expect
		.poll(() =>
			sql(
				`select count(*) from public.conflicts where scholarid = '${declarerID}' and submissionid = '${SUBMISSION_ID}';`
			)
		)
		.toBe('1');

	// The submission is no longer present in the scholar's submissions list
	// (the page filters out conflicted submissions for them).
	await page.reload();
	await page.waitForLoadState('networkidle');
	await expect(page.locator('text=TOK-2025-001')).toHaveCount(0);
});

test('editor toggles a submission as review-complete and its status flips reviewing → done', async ({
	page,
	context
}) => {
	// Start from a known reviewing state so the toggle has work to do.
	sql(`update public.submissions set status = 'reviewing' where id = '${SUBMISSION_ID}';`);

	await login(EDITOR_EMAIL, page, context);
	await page.goto(`/venue/${VENUE_ID}/submission/${SUBMISSION_ID}`);
	await page.waitForLoadState('networkidle');

	await page.getByTestId('submission-review-complete').click();

	await expect
		.poll(() => sql(`select status::text from public.submissions where id = '${SUBMISSION_ID}';`))
		.toBe('done');

	// Toggle off again to restore state for other tests.
	await page.getByTestId('submission-review-complete').click();
	await expect
		.poll(() => sql(`select status::text from public.submissions where id = '${SUBMISSION_ID}';`))
		.toBe('reviewing');
});

test('reviewer-anonymity flag actually hides assignees from authors', async ({ page, context }) => {
	// Ensure the venue is in its default anonymous state.
	sql(`update public.venues set anonymous_assignments = true where id = '${VENUE_ID}';`);

	await login(AUTHOR_EMAIL, page, context);
	await page.goto(`/venue/${VENUE_ID}/submission/${SUBMISSION_ID}`);
	await page.waitForLoadState('networkidle');

	// As the author, with anonymity on, the assigned reviewer's name (r1,
	// Rigor Russ) is NOT visible on the page — RLS at
	// supabase/schemas/assignments.sql L199-226 hides the assignment row.
	await expect(page.getByText(ASSIGNED_REVIEWER_NAME)).toHaveCount(0);

	// Flip anonymity off and reload; now the reviewer's name is visible.
	sql(`update public.venues set anonymous_assignments = false where id = '${VENUE_ID}';`);
	await page.reload();
	await page.waitForLoadState('networkidle');
	await expect(page.getByText(ASSIGNED_REVIEWER_NAME).first()).toBeVisible();

	// Restore the default for other tests.
	sql(`update public.venues set anonymous_assignments = true where id = '${VENUE_ID}';`);
});

test('approver-role hierarchy: AE approves a Reviewer bid; a non-approver does not see the approve button', async ({
	page,
	context
}) => {
	// Ensure there's at least one unapproved Reviewer bid on the seed
	// submission. Reset to bid=true, approved=false so the test is repeatable.
	sql(
		`update public.assignments set approved = false, bid = true where submission = '${SUBMISSION_ID}' and role = '${REVIEWER_ROLE_ID}' and bid = true;`
	);

	// Negative case first: log in as a Reviewer (r2). r2 has the Reviewer
	// role but is NOT the approver of the Reviewer role (the AE is). r2 also
	// isn't a venue admin. So r2 should not see the bid-approve button.
	await login('r2@uni.edu', page, context);
	await page.goto(`/venue/${VENUE_ID}/submission/${SUBMISSION_ID}`);
	await page.waitForLoadState('networkidle');
	await expect(
		page.getByRole('button', {
			name: 'Accept this bid, assigning this scholar to this role for this submission'
		})
	).toHaveCount(0);

	// Positive case: log in as the AE (the approver of the Reviewer role,
	// holding their own approved AE assignment on this submission, which is
	// itself an invite-only role per the seed). The bid-approve button is
	// present, and clicking it flips the bid's approved=true.
	await context.clearCookies();
	await login('ae@uni.edu', page, context);
	await page.goto(`/venue/${VENUE_ID}/submission/${SUBMISSION_ID}`);
	await page.waitForLoadState('networkidle');

	const approveCount = Number(
		sql(
			`select count(*) from public.assignments where submission = '${SUBMISSION_ID}' and role = '${REVIEWER_ROLE_ID}' and approved = true;`
		)
	);

	const approveButton = page
		.getByRole('button', {
			name: 'Accept this bid, assigning this scholar to this role for this submission'
		})
		.first();
	await expect(approveButton).toBeVisible();
	await approveButton.click();

	await expect
		.poll(() =>
			Number(
				sql(
					`select count(*) from public.assignments where submission = '${SUBMISSION_ID}' and role = '${REVIEWER_ROLE_ID}' and approved = true;`
				)
			)
		)
		.toBe(approveCount + 1);
});
