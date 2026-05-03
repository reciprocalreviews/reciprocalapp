import { expect, test } from '@playwright/test';
import { login, logout } from '../src/routes/login';

const VENUE_ID = 'c60d7d0a-ad37-11f0-83e5-efb2eb8bdbd6';
const AUTHOR1_ORCID = '0000-0001-2345-6792'; // Foot Note (author1@uni.edu)
const AUTHOR2_ORCID = '0000-0001-2345-6795'; // Ann Thesis (author2@uni.edu)

test('author can create a two-author submission splitting the cost', async ({ page, context }) => {
	await login('author1@uni.edu', page, context);

	await page.goto(`/venue/${VENUE_ID}/submissions/new`);
	await page.waitForLoadState('networkidle');

	// Fill in the required submission details. The external ID is unique per
	// run because the venue+externalid pair is enforced unique in the DB.
	await page.getByTestId('submission-title').fill('A Study of Reciprocal Review Incentives');
	await page.getByTestId('submission-manuscript-id').fill(`TOK-2026-TEST-${Date.now()}`);

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

	// Submit and verify redirect to the new submission page.
	await page.getByTestId('submit-submission').click();
	await page.waitForURL(/\/venue\/.+\/submission\/.+/);

	await logout(page);
});
