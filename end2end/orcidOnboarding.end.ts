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
	// The mock ORCID fields render only off-production (the dev login form).
	await page.getByTestId('mock-orcid-id').fill(MOCK_ORCID);
	await page.getByTestId('mock-orcid-name').fill('Onboarding Tester');
	await page.getByTestId('orcid-signin').click();
	await page.waitForURL(/\/scholar\/.+/);

	// handle_new_scholar created a fresh scholar with the mocked orcid/name and — like a
	// real first ORCID sign-in — a NULL contact email.
	await expect
		.poll(() => sql(`select count(*) from public.scholars where orcid = '${MOCK_ORCID}';`))
		.toBe('1');
	expect(sql(`select coalesce(email, '<null>') from public.scholars where orcid = '${MOCK_ORCID}';`)).toBe(
		'<null>'
	);
	expect(sql(`select name from public.scholars where orcid = '${MOCK_ORCID}';`)).toBe(
		'Onboarding Tester'
	);

	// The unverified-email banner prompts the new scholar to add an email.
	await expect(page.getByTestId('banner-email')).toBeVisible();
});
