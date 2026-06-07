import { expect, test } from '@playwright/test';
import { login } from '../src/routes/login';
import { SEED, sql } from './test-utils';

const VENUE_ID = SEED.venue;
const SUBMISSION_ID = SEED.submissions.tok001; // TOK-2025-001
const EDITOR_EMAIL = SEED.scholars.editor.email;
const EDITOR_ID = SEED.scholars.editor.id;
const AUTHOR_EMAIL = SEED.scholars.author1.email; // author of TOK-2025-001
const CONFLICT_DECLARER_EMAIL = SEED.scholars.r3.email; // Reviewer volunteer with no assignments
const ASSIGNED_REVIEWER_NAME = SEED.scholars.r1.name; // r1, the approved Reviewer on TOK-2025-001
const REVIEWER_ROLE_ID = SEED.roles.reviewer;

test('editor manually adds a single submission with themselves as the sole author', async ({
	page,
	context
}) => {
	// createSubmission does several sequential DB round-trips before the goto(),
	// and the waitForURL below allows 60s; give the test a budget larger than
	// that so a slow CI runner doesn't trip the 30s default first.
	test.setTimeout(120_000);

	// Get the editor's actual ORCID from the DB so the form's blur-based
	// scholar lookup resolves to the editor's scholar record.
	const editorOrcid = sql(`select orcid from public.scholars where id = '${EDITOR_ID}';`);

	const externalID = `EDITOR-ADD-${Date.now()}`;

	await login(EDITOR_EMAIL, page, context);
	await page.goto(`/venue/${VENUE_ID}/submissions/new`);
	// Keep networkidle here: the submission form's bound <select>/inputs must be
	// hydrated before we selectOption/fill, or Svelte drops the change.
	await page.waitForLoadState('networkidle');

	// Submit as a "Research Article" (cost 10).
	await page
		.getByRole('combobox', { name: 'submission type' })
		.selectOption({ label: 'Research Article' });
	await page.getByTestId('submission-title').fill('Editor-authored single submission');
	await page.getByTestId('submission-manuscript-id').fill(externalID);

	await page.getByTestId('author-orcid-0').fill(editorOrcid);
	await page.getByTestId('author-orcid-0').blur();
	await expect(page.getByTestId('scholar-found-0')).toBeVisible();

	// Pay the submission type's full cost (10) as the sole author.
	await page.getByTestId('payment-slider-0').fill('10');

	await page.getByTestId('check-balances').click();
	await expect(
		page.locator('text=The authors have sufficient tokens to pay for this submission.')
	).toBeVisible();

	// The submit button briefly re-disables whenever a charge field changes
	// (NewSubmission resets affordability in a $effect), so wait for it to settle
	// enabled before clicking rather than firing a no-op click.
	const submit = page.getByTestId('submit-submission');
	await expect(submit).toBeEnabled({ timeout: 5_000 });
	await page.waitForTimeout(200);
	await submit.click();

	// createSubmission runs several sequential DB round-trips before it navigates.
	// Confirm the row landed (generous poll) before waiting on the redirect, so a
	// slow server round-trip surfaces as a clear "row not created" failure instead
	// of an opaque navigation timeout, and the redirect wait only covers the nav.
	await expect
		.poll(
			() => sql(`select count(*) from public.submissions where externalid = '${externalID}';`),
			{ timeout: 90_000 }
		)
		.toBe('1');
	await page.waitForURL(/\/venue\/.+\/submission\/.+/, { timeout: 30_000 });

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
	await expect(page.locator('text=TOK-2025-001')).toHaveCount(0);
});

test('mark-done is blocked until non-editor assignments are compensated, then flips status', async ({
	page,
	context
}) => {
	// Force a known starting state. Direct UPDATEs on status/completed_at
	// are revoked from authenticated, but the seed's psql role is the
	// superuser so this is allowed at the DB level for test setup/teardown.
	sql(
		`update public.submissions set status = 'reviewing', completed_at = null where id = '${SUBMISSION_ID}';`
	);
	// Leave the editor's own priority-0 assignment uncompleted (the
	// mark-done action will compensate it). Reset every non-editor
	// approved assignment to uncompleted so the button starts inactive.
	sql(
		`update public.assignments set completed = false where submission = '${SUBMISSION_ID}' and approved;`
	);

	await login(EDITOR_EMAIL, page, context);
	await page.goto(`/venue/${VENUE_ID}/submission/${SUBMISSION_ID}`);

	// Button exists but is disabled while non-editor assignments are
	// pending, and the blockers list is visible.
	await expect(page.getByTestId('mark-submission-done')).toBeDisabled();

	// Mark every non-editor approved assignment as completed in the DB
	// (simulates the editor working through each Complete button). Kept on
	// one line because `sql()` passes the string through `psql -c`, which
	// receives literal `\n` if newlines survive JSON.stringify.
	sql(
		`update public.assignments a set completed = true from public.roles r where a.role = r.id and a.submission = '${SUBMISSION_ID}' and a.approved and r.priority > 0;`
	);

	await page.reload();
	await page.waitForLoadState('networkidle');

	await expect(page.getByTestId('mark-submission-done')).toBeEnabled();

	// Confirm-style button: first click reveals the warn variant, second confirms.
	await page.getByTestId('mark-submission-done').click();
	await page.getByTestId('mark-submission-done').click();

	await expect
		.poll(() => sql(`select status::text from public.submissions where id = '${SUBMISSION_ID}';`))
		.toBe('done');

	// The editor's own assignment is now completed as part of the action.
	await expect
		.poll(() =>
			sql(
				`select completed from public.assignments where submission = '${SUBMISSION_ID}' and scholar = '${EDITOR_ID}';`
			)
		)
		.toBe('t');

	// Reopening is forbidden by design — restore state for downstream
	// tests via SQL only (the UI cannot revert).
	sql(
		`update public.submissions set status = 'reviewing', completed_at = null where id = '${SUBMISSION_ID}';`
	);
	sql(
		`update public.assignments set completed = false where submission = '${SUBMISSION_ID}' and approved;`
	);
});

test('reviewer-anonymity flag actually hides assignees from authors', async ({ page, context }) => {
	// Ensure the venue is in its default anonymous state.
	sql(`update public.venues set anonymous_assignments = true where id = '${VENUE_ID}';`);

	await login(AUTHOR_EMAIL, page, context);
	await page.goto(`/venue/${VENUE_ID}/submission/${SUBMISSION_ID}`);

	// As the author, with anonymity on, the assigned reviewer's name (r1,
	// Rigor Russ) is NOT visible on the page — RLS at
	// supabase/schemas/assignments.sql L199-226 hides the assignment row.
	await expect(page.getByText(ASSIGNED_REVIEWER_NAME)).toHaveCount(0);

	// Flip anonymity off and reload; now the reviewer's name is visible.
	sql(`update public.venues set anonymous_assignments = false where id = '${VENUE_ID}';`);
	await page.reload();
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
