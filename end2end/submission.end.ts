import { expect, test } from '@playwright/test';
import { login, logout } from '../src/routes/login';
import { SEED, sql } from './test-utils';

const VENUE_ID = SEED.venue;
const AUTHOR1_ORCID = SEED.scholars.author1.orcid; // Foot Note (author1@uni.edu)
const AUTHOR2_ORCID = SEED.scholars.author2.orcid; // Ann Thesis (author2@uni.edu)

test('author can create a two-author submission splitting the cost', async ({ page, context }) => {
	// Submission creation does several sequential DB round-trips (verify
	// balances, find scholars, fetch venue, create proposed transactions,
	// approve the creator's transaction, insert the submission, then load the
	// new submission page). The default 30s test budget is enough locally but
	// flaky on CI runners.
	test.setTimeout(120_000);

	await login('author1@uni.edu', page, context);

	const externalID = `TOK-2026-TEST-${Date.now()}`;

	await page.goto(`/venue/${VENUE_ID}/submissions/new`);
	// Keep networkidle here: the submission form's bound <select>/inputs must be
	// hydrated before we selectOption/fill, or Svelte drops the change. (Most
	// other pages replaced this with an explicit content wait.)
	await page.waitForLoadState('networkidle');

	// Submit as a "Research Article" (cost 10, split 5+5 below).
	await page
		.getByRole('combobox', { name: 'submission type' })
		.selectOption({ label: 'Research Article' });

	// Fill in the required submission details. The external ID is unique per
	// run because the venue+externalid pair is enforced unique in the DB.
	await page.getByTestId('submission-title').fill('A Study of Reciprocal Review Incentives');
	await page.getByTestId('submission-manuscript-id').fill(externalID);

	// In case there's a failure, scroll down so we have a screenshot.
	await page.getByTestId('add-author').scrollIntoViewIfNeeded();

	// Enter author1's ORCID and Tab out to trigger the blur-based lookup.
	await page.getByTestId('author-orcid-0').fill(AUTHOR1_ORCID);
	await page.getByTestId('author-orcid-0').blur();
	await expect(page.getByTestId('scholar-found-0')).toBeVisible();

	// Add a second author row.
	await page.getByTestId('add-author').click();

	// Enter author2's ORCID and wait for the lookup the same way.
	await page.getByTestId('author-orcid-1').fill(AUTHOR2_ORCID);
	await page.getByTestId('author-orcid-1').blur();
	await page.getByTestId('author-orcid-1').scrollIntoViewIfNeeded();
	await expect(page.getByTestId('scholar-found-1')).toBeVisible();

	// Set each author's payment to 5 tokens (total = 10 = submission cost).
	await page.getByTestId('payment-slider-0').fill('5');
	await page.getByTestId('payment-slider-1').fill('5');

	// Check that both authors can afford the payment. It should be enabled
	await page.getByTestId('check-balances').click();
	await expect(
		page.locator('text=The authors have sufficient tokens to pay for this submission.')
	).toBeVisible();

	// Submit and verify redirect to the new submission page. We need a more
	// generous URL-wait timeout than the action default because the underlying
	// createSubmission does several sequential DB round-trips before goto().
	//
	// NewSubmission.svelte runs a $effect that resets the affordable state
	// (and therefore disables the submit button) whenever any charge field
	// touches. Under CI's slower JS scheduler the button can briefly flicker
	// disabled between Playwright's auto-wait and the click, so we explicitly
	// wait for it to be enabled and let reactive state settle before clicking.
	const submitButton = page.getByTestId('submit-submission');
	await expect(submitButton).toBeEnabled({ timeout: 5_000 });
	await page.waitForTimeout(200);
	await submitButton.click();

	// Confirm the submission landed server-side (generous poll) before waiting on
	// the redirect, so a slow createSubmission round-trip surfaces as a clear
	// failure instead of an opaque navigation timeout.
	await expect
		.poll(
			() => sql(`select count(*) from public.submissions where externalid = '${externalID}';`),
			{ timeout: 90_000 }
		)
		.toBe('1');
	await page.waitForURL(/\/venue\/.+\/submission\/.+/, { timeout: 30_000 });

	await logout(page);
});

test('author can link a resubmission to a prior submission and is charged the resubmission cost', async ({
	page,
	context
}) => {
	// Two full submission flows back to back, each with several sequential DB
	// round-trips, so we extend the budget the same way the single-submission
	// test above does.
	test.setTimeout(150_000);

	await login('author1@uni.edu', page, context);

	const originalTitle = 'Resubmission Test Original';
	const originalID = `TOK-ORIG-${Date.now()}`;

	// 1. Create the original submission as the sole author, paying the venue's
	// regular submission cost of 10 tokens.
	await page.goto(`/venue/${VENUE_ID}/submissions/new`);
	// Keep networkidle here: the submission form's bound <select>/inputs must be
	// hydrated before we selectOption/fill, or Svelte drops the change. (Most
	// other pages replaced this with an explicit content wait.)
	await page.waitForLoadState('networkidle');

	// Submit as a "Research Article" (cost 10).
	await page
		.getByRole('combobox', { name: 'submission type' })
		.selectOption({ label: 'Research Article' });
	await page.getByTestId('submission-title').fill(originalTitle);
	await page.getByTestId('submission-manuscript-id').fill(originalID);
	await page.getByTestId('author-orcid-0').fill(AUTHOR1_ORCID);
	await page.getByTestId('author-orcid-0').blur();
	await expect(page.getByTestId('scholar-found-0')).toBeVisible();
	await page.getByTestId('payment-slider-0').fill('10');

	await page.getByTestId('check-balances').click();
	await expect(
		page.locator('text=The authors have sufficient tokens to pay for this submission.')
	).toBeVisible();

	const submitOriginal = page.getByTestId('submit-submission');
	await expect(submitOriginal).toBeEnabled({ timeout: 5_000 });
	await page.waitForTimeout(200);
	await submitOriginal.click();
	await expect
		.poll(() => sql(`select count(*) from public.submissions where externalid = '${originalID}';`), {
			timeout: 90_000
		})
		.toBe('1');
	await page.waitForURL(/\/venue\/.+\/submission\/.+/, { timeout: 30_000 });

	// 2. Create a resubmission linking the original. Start from the plain
	// "Research Article" type (cost 10), then let the predecessor pick the type.
	await page.goto(`/venue/${VENUE_ID}/submissions/new`);
	// Keep networkidle here: the submission form's bound <select>/inputs must be
	// hydrated before we selectOption/fill, or Svelte drops the change. (Most
	// other pages replaced this with an explicit content wait.)
	await page.waitForLoadState('networkidle');

	const typePicker = page.getByRole('combobox', { name: 'submission type' });
	await typePicker.selectOption({ label: 'Research Article' });
	await expect(page.getByTestId('payment-slider-0')).toHaveAttribute('max', '10');

	// The picker lists the author's prior submissions to this venue. Select the
	// one we just created (labeled "<external id> — <title>").
	const picker = page.getByRole('combobox', { name: 'previous submission' });
	await expect(picker).toBeVisible();
	await picker.selectOption({ label: `${originalID} — ${originalTitle}` });

	// Linking a predecessor mirrors its external ID into the (now locked)
	// previous-manuscript-ID field, auto-selects the matching revision type, and
	// so switches the cost to that type's cost (4).
	const previousIDField = page.getByTestId('submission-previous-id');
	await expect(previousIDField).toHaveValue(originalID);
	await expect(previousIDField).toBeDisabled();
	await expect(typePicker.locator('option:checked')).toHaveText('Research Article - Revision');
	await expect(page.getByTestId('payment-slider-0')).toHaveAttribute('max', '4');

	const resubmissionID = `TOK-RESUB-${Date.now()}`;
	await page.getByTestId('submission-title').fill('Resubmission Test Revised');
	await page.getByTestId('submission-manuscript-id').fill(resubmissionID);
	await page.getByTestId('author-orcid-0').fill(AUTHOR1_ORCID);
	await page.getByTestId('author-orcid-0').blur();
	await expect(page.getByTestId('scholar-found-0')).toBeVisible();
	await page.getByTestId('payment-slider-0').fill('4');

	await page.getByTestId('check-balances').click();
	await expect(
		page.locator('text=The authors have sufficient tokens to pay for this submission.')
	).toBeVisible();

	const submitResubmission = page.getByTestId('submit-submission');
	await expect(submitResubmission).toBeEnabled({ timeout: 5_000 });
	await page.waitForTimeout(200);
	await submitResubmission.click();
	await expect
		.poll(
			() => sql(`select count(*) from public.submissions where externalid = '${resubmissionID}';`),
			{ timeout: 90_000 }
		)
		.toBe('1');
	await page.waitForURL(/\/venue\/.+\/submission\/.+/, { timeout: 30_000 });

	// 3. The resubmission detail page links back to its predecessor by external ID.
	await expect(page.getByRole('link', { name: originalID })).toBeVisible();

	await logout(page);
});
