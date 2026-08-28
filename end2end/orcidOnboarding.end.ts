import { test, expect } from '@playwright/test';
import { sql } from './test-utils';

// A format-valid ORCID iD unique to this test; the dev-only mock ORCID sign-in creates a
// brand-new scholar for it (custom OIDC can't run locally — see Auth.svelte.ts).
const MOCK_ORCID = '0009-0006-4477-1001';

test('mock ORCID sign-in onboards a new scholar with no email and shows the banner', async ({
	page
}) => {
	test.setTimeout(60_000);

	await page.goto('/login');
	// The mock ORCID fields render only off-production, and now live in a
	// collapsed card — it mints a new scholar rather than signing anyone in, so
	// it sits below the sign-in table rather than above it.
	await page.getByTestId('mock-orcid-card').click();
	await page.getByTestId('mock-orcid-id').fill(MOCK_ORCID);
	await page.getByTestId('mock-orcid-name').fill('Onboarding Tester');
	await page.getByTestId('orcid-signin').click();
	await page.waitForURL(/\/scholar\/.+/);

	// handle_new_scholar created a fresh scholar with the mocked orcid/name and — like a
	// real first ORCID sign-in — a NULL contact email.
	await expect
		.poll(() => sql(`select count(*) from public.scholars where orcid = '${MOCK_ORCID}';`))
		.toBe('1');
	expect(
		sql(`select coalesce(email, '<null>') from public.scholars where orcid = '${MOCK_ORCID}';`)
	).toBe('<null>');
	expect(sql(`select name from public.scholars where orcid = '${MOCK_ORCID}';`)).toBe(
		'Onboarding Tester'
	);

	// The unverified-email banner prompts the new scholar to add an email.
	await expect(page.getByTestId('banner-email')).toBeVisible();
});

test('the local sign-in list signs in a seeded scholar in one click', async ({ page }) => {
	// Testing a flow as a particular scholar used to mean opening seed.sql for
	// their address and recalling the shared password. Local stacks only — the
	// same gate as the password form, since these accounts exist nowhere else.
	await page.goto('/login');
	await page.waitForLoadState('networkidle');

	await expect(page.getByTestId('seeded-dev')).toBeVisible();

	// Each row says what the account can do, which is what decides which one you
	// want for the flow under test.
	await expect(page.getByText(/steward/)).toBeVisible();
	await expect(page.getByText(/admin of Transactions on Knowledge/)).toBeVisible();
	await expect(page.getByText(/minter of Epistemology/)).toBeVisible();

	// Pick the editor by address rather than by position. Sign-in uses the
	// scholar's *contact* email, which the email-verification spec changes for
	// another scholar — and a contact address that has diverged from the auth
	// identity can no longer be signed in with, which is what showing the address
	// in its own column is there to reveal.
	await page.getByRole('row').filter({ hasText: 'editor@uni.edu' }).getByRole('button').click();
	await page.waitForURL(/\/scholar\/.+/, { timeout: 20_000 });
});
