import { test, expect } from '@playwright/test';
import { login } from '../src/routes/login';
import { SEED, sql } from './test-utils';

// Contact-email verification (#27). r5 is otherwise unreferenced by the suite, so we
// can freely mutate her contact email here without disturbing other specs.
const R5 = SEED.scholars.r5;

test('an unverified scholar sees the banner and can verify a new contact email', async ({
	page,
	context
}) => {
	test.setTimeout(60_000);

	// Put r5 in the "no verified email" state a new ORCID sign-in would land in.
	sql(`update public.scholars set email = null where id = '${R5.id}';`);

	await login(R5.email, page, context);
	await page.goto(`/scholar/${R5.id}`);
	// The EditableText email field is hydration-gated; wait before interacting.
	await page.waitForLoadState('networkidle');

	// The persistent unverified-email banner is shown.
	await expect(page.getByTestId('banner-email')).toBeVisible();

	// Request verification for a new address via the profile email field.
	const newEmail = `verified${Date.now()}@uni.edu`;
	await page.getByTestId('scholar-email-toggle').click();
	const field = page.getByTestId('scholar-email');
	await expect(field).toBeEditable();
	await field.fill(newEmail);
	await field.blur();

	// A verification email is queued to the new address, but scholars.email is NOT
	// updated yet — only verifying the token commits it.
	await expect
		.poll(() =>
			sql(`select count(*) from public.emails where event = 'VerifyEmail' and email = '${newEmail}';`)
		)
		.toBe('1');
	expect(sql(`select coalesce(email, '') from public.scholars where id = '${R5.id}';`)).toBe('');

	// Pull the single-use token out of the queued email's body and visit the link.
	const token = sql(
		`select substring(message from '/verify/([a-f0-9]+)') from public.emails where event = 'VerifyEmail' and email = '${newEmail}' limit 1;`
	);
	expect(token).toMatch(/^[a-f0-9]{64}$/);

	await page.goto(`/verify/${token}`);
	await expect(page.getByTestId('verify-verified')).toBeVisible();

	// The address is now committed to scholars.email...
	await expect
		.poll(() => sql(`select email from public.scholars where id = '${R5.id}';`))
		.toBe(newEmail);

	// ...and the banner is gone on the next page load.
	await page.goto(`/scholar/${R5.id}`);
	await expect(page.getByTestId('banner-email')).toBeHidden();
});

test('an already-used or unknown verification link shows the invalid state', async ({ page }) => {
	await page.goto('/verify/deadbeefdeadbeef');
	await expect(page.getByTestId('verify-invalid')).toBeVisible();
});

test('an expired verification link shows the expired state and preserves the email', async ({
	page
}) => {
	const raw = `expiredtoken${Date.now()}`;
	sql(
		`insert into public.email_verifications (scholar, token_hash, candidate_email, expires_at) values ('${R5.id}', encode(extensions.digest('${raw}', 'sha256'), 'hex'), 'later@uni.edu', now() - interval '1 minute') on conflict (scholar) do update set token_hash = excluded.token_hash, candidate_email = excluded.candidate_email, expires_at = excluded.expires_at;`
	);
	await page.goto(`/verify/${raw}`);
	await expect(page.getByTestId('verify-expired')).toBeVisible();
	// The expired candidate ('later@uni.edu') was never committed.
	expect(sql(`select coalesce(email, '') from public.scholars where id = '${R5.id}';`)).not.toBe(
		'later@uni.edu'
	);
});
