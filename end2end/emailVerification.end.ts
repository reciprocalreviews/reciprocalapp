import { test, expect } from '@playwright/test';
import { login } from '../src/routes/login';
import { SEED, sql } from './test-utils';

// Contact-email verification (#27). r5 is the scholar whose contact email this file
// mutates, because no other spec asserts anything about her ADDRESS.
//
// She is not, however, unreferenced: r5 is an active accepted Reviewer in the seed, so
// reviewerAssignment.end.ts can assign her a bid and reviewerCompensation.end.ts can then
// compensate her — and compensation reports success partly on having notified the reviewer,
// which is impossible for a scholar with no verified address. Leaving her without one at the
// end of this file therefore breaks a spec two files later, with a failure that looks
// nothing like its cause. Hence the afterAll below: this file puts her back.
const R5 = SEED.scholars.r5;
// r4 already has a verified email — used to exercise the change flow.
const R4 = SEED.scholars.r4;

// Restore r5 to her seed state. Every test here leaves her mid-flow by design — no address,
// or one still awaiting confirmation — and the suite runs against one shared database.
test.afterAll(() => {
	sql(`delete from public.email_verifications where scholar = '${R5.id}';`);
	sql(`update public.scholars set email = '${R5.email}' where id = '${R5.id}';`);
});

test('an unverified scholar sees the banner and can verify a new contact email', async ({
	page,
	context
}) => {
	test.setTimeout(60_000);

	// Put r5 in the "no verified email" state a new ORCID sign-in would land in.
	sql(`update public.scholars set email = null where id = '${R5.id}';`);

	await login(R5.email, page, context);
	await page.goto(`/scholar/${R5.id}`);
	await page.waitForLoadState('networkidle');

	// The persistent unverified-email banner is shown.
	await expect(page.getByTestId('banner-email')).toBeVisible();

	// The profile prompts for a contact email; request verification for a new address.
	const newEmail = `verified${Date.now()}@uni.edu`;
	await expect(page.getByTestId('email-onboarding')).toBeVisible();
	await page.getByTestId('verify-email-input').fill(newEmail);
	await page.getByTestId('verify-email-submit').click();
	await expect(page.getByTestId('verify-email-sent')).toBeVisible();

	// A verification email is queued to the new address, but scholars.email is NOT
	// updated yet — only verifying the token commits it.
	await expect
		.poll(() =>
			sql(
				`select count(*) from public.emails where event = 'VerifyEmail' and email = '${newEmail}';`
			)
		)
		.toBe('1');
	expect(sql(`select coalesce(email, '') from public.scholars where id = '${R5.id}';`)).toBe('');

	// Pull the token out of the queued email and visit the link. It lives in `args` (the
	// email is rendered at send time, so `message` is null): the token is generated inside
	// request_email_verification and never reaches the client, so reading the queued row as
	// the service role is the only way to obtain it — which is the point of the design.
	const token = sql(
		`select substring(args->>0 from '/verify/([a-f0-9]+)') from public.emails where event = 'VerifyEmail' and email = '${newEmail}' limit 1;`
	);
	expect(token).toMatch(/^[a-f0-9]{64}$/);

	await page.goto(`/verify/${token}`);
	await expect(page.getByTestId('verify-verified')).toBeVisible();

	// Verification is idempotent within the window: re-fetching the same link (as a
	// preloading email scanner would) still shows verified, not a misleading invalid.
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
	// verified_at and email_id are both reset explicitly, because this hand-written upsert
	// has to do what request_email_verification's does. A confirmed request now wins over the
	// clock — it has to, or a scholar reopening a two-day-old message would be told a link
	// expired for an address that is already theirs — and an earlier test in this file leaves
	// r5 with a confirmed row, whose stamp this would otherwise inherit. email_id likewise
	// points at whatever message the previous test queued, and a stale one carrying a failed
	// delivery would make this request report itself undelivered rather than expired.
	sql(
		`insert into public.email_verifications (scholar, token_hash, candidate_email, expires_at, verified_at, email_id) values ('${R5.id}', encode(extensions.digest('${raw}', 'sha256'), 'hex'), 'later@uni.edu', now() - interval '1 minute', null, null) on conflict (scholar) do update set token_hash = excluded.token_hash, candidate_email = excluded.candidate_email, expires_at = excluded.expires_at, verified_at = excluded.verified_at, email_id = excluded.email_id;`
	);
	await page.goto(`/verify/${raw}`);
	await expect(page.getByTestId('verify-expired')).toBeVisible();
	// The expired candidate ('later@uni.edu') was never committed.
	expect(sql(`select coalesce(email, '') from public.scholars where id = '${R5.id}';`)).not.toBe(
		'later@uni.edu'
	);
	// The request SURVIVES expiry, where it used to be deleted. This is what the resend
	// affordance hangs on: without the row there is no record of which address was pending,
	// and the only thing the interface could offer was a blank form.
	expect(sql(`select count(*) from public.email_verifications where scholar = '${R5.id}';`)).toBe(
		'1'
	);
});

test('a pending verification survives a reload, and can be sent again', async ({
	page,
	context
}) => {
	test.setTimeout(90_000);

	// Start from the state a scholar with nothing verified is in.
	sql(`update public.scholars set email = null where id = '${R5.id}';`);
	sql(`delete from public.email_verifications where scholar = '${R5.id}';`);

	await login(R5.email, page, context);
	await page.goto(`/scholar/${R5.id}`);
	await page.waitForLoadState('networkidle');

	const pendingEmail = `pending${Date.now()}@uni.edu`;
	await page.getByTestId('verify-email-input').fill(pendingEmail);
	await page.getByTestId('verify-email-submit').click();
	await expect(page.getByTestId('verify-email-sent')).toBeVisible();

	// The regression test for the whole persistence change. "We sent you a link" used to be
	// a boolean in component memory, so a reload showed the same empty form again with no
	// sign that anything was on its way or which address it went to.
	await page.reload();
	await page.waitForLoadState('networkidle');
	const pending = page.getByTestId('verify-email-pending');
	await expect(pending).toBeVisible();
	await expect(pending).toContainText(pendingEmail);

	// Within the database's one-minute cooldown the button is disabled and says when it
	// will work, rather than letting the scholar hit the refusal as an error.
	await expect(page.getByTestId('verify-email-resend')).toBeDisabled();
	await expect(page.getByTestId('verify-email-cooldown')).toBeVisible();

	// Wind the clock past the cooldown rather than waiting out a real minute.
	sql(
		`update public.email_verifications set created_at = created_at - interval '2 minutes' where scholar = '${R5.id}';`
	);
	await page.reload();
	await page.waitForLoadState('networkidle');

	const resend = page.getByTestId('verify-email-resend');
	await expect(resend).toBeEnabled();
	await resend.click();
	await expect(page.getByTestId('verify-email-sent')).toBeVisible();

	// A second link went out to the same address, and the cooldown restarted.
	await expect
		.poll(() =>
			sql(
				`select count(*) from public.emails where event = 'VerifyEmail' and email = '${pendingEmail}';`
			)
		)
		.toBe('2');
	await expect(page.getByTestId('verify-email-resend')).toBeDisabled();
});

test('a verification email that never went out says so', async ({ page, context }) => {
	test.setTimeout(60_000);

	sql(`update public.scholars set email = null where id = '${R5.id}';`);
	sql(`delete from public.email_verifications where scholar = '${R5.id}';`);

	await login(R5.email, page, context);
	await page.goto(`/scholar/${R5.id}`);
	await page.waitForLoadState('networkidle');

	const undelivered = `undelivered${Date.now()}@uni.edu`;
	await page.getByTestId('verify-email-input').fill(undelivered);
	await page.getByTestId('verify-email-submit').click();
	await expect(page.getByTestId('verify-email-sent')).toBeVisible();

	// Written directly rather than by actually breaking delivery. The suite runs without an
	// edge runtime, so every send in it genuinely fails — but the reconciler that would
	// notice is unscheduled for the run (see global-setup.ts), precisely so this surface is
	// exercised deterministically instead of whenever a cron job happened to fire.
	sql(
		`update public.emails set delivery = 'failed', delivery_detail = '502: test' where id = (select email_id from public.email_verifications where scholar = '${R5.id}');`
	);

	await page.reload();
	await page.waitForLoadState('networkidle');
	const failed = page.getByTestId('verify-email-undelivered');
	await expect(failed).toBeVisible();
	await expect(failed).toContainText(undelivered);
	// The failure replaces the "it's on its way" notice rather than sitting beside it.
	await expect(page.getByTestId('verify-email-pending')).toBeHidden();
});

test('an expired link offers a resend to its owner, and sign-in to everyone else', async ({
	page,
	context
}) => {
	test.setTimeout(90_000);

	sql(`update public.scholars set email = null where id = '${R5.id}';`);
	const raw = `expiredresend${Date.now()}`;
	sql(
		`insert into public.email_verifications (scholar, token_hash, candidate_email, created_at, expires_at, verified_at, email_id) values ('${R5.id}', encode(extensions.digest('${raw}', 'sha256'), 'hex'), 'lapsed@uni.edu', now() - interval '2 days', now() - interval '1 day', null, null) on conflict (scholar) do update set token_hash = excluded.token_hash, candidate_email = excluded.candidate_email, created_at = excluded.created_at, expires_at = excluded.expires_at, verified_at = excluded.verified_at, email_id = excluded.email_id;`
	);

	// Signed out first: resending acts on auth.uid(), not on the token, and EXECUTE on the
	// RPC is revoked from anon — so the only thing this visitor can be offered is a sign-in.
	await page.goto(`/verify/${raw}`);
	await expect(page.getByTestId('verify-expired')).toBeVisible();
	await expect(page.getByTestId('verify-email-resend')).toBeHidden();

	// Signed in as the owner, the dead end becomes one button.
	await login(R5.email, page, context);
	await page.goto(`/verify/${raw}`);
	await page.waitForLoadState('networkidle');
	// One notice, not two: the component's names the address, so the page's generic
	// "this link has expired" is suppressed rather than stacked on top of it.
	await expect(page.getByTestId('verify-expired')).toBeHidden();
	await expect(page.getByTestId('verify-email-expired')).toContainText('lapsed@uni.edu');
	const resend = page.getByTestId('verify-email-resend');
	await expect(resend).toBeEnabled();
	await resend.click();

	await expect
		.poll(() =>
			sql(
				`select count(*) from public.emails where event = 'VerifyEmail' and email = 'lapsed@uni.edu';`
			)
		)
		.toBe('1');
	// A fresh 24-hour window, so the scholar is no longer looking at a lapsed request.
	expect(
		sql(`select expires_at > now() from public.email_verifications where scholar = '${R5.id}';`)
	).toBe('t');
});

test('changing an email trims whitespace and sends; an unchanged address sends nothing', async ({
	page,
	context
}) => {
	test.setTimeout(60_000);

	await login(R4.email, page, context);
	await page.goto(`/scholar/${R4.id}`);
	await page.waitForLoadState('networkidle');

	// The current address shows with an Edit affordance (EditableText change flow).
	const newEmail = `changed${Date.now()}@uni.edu`;
	await page.getByTestId('scholar-email-toggle').click();
	const field = page.getByTestId('scholar-email');
	await expect(field).toBeEditable();
	await field.fill(`   ${newEmail}   `); // surrounding whitespace is trimmed
	await field.blur();

	// A verification email is queued to the TRIMMED address; scholars.email is unchanged
	// until it's verified.
	await expect(page.getByTestId('verify-email-sent')).toBeVisible();
	await expect
		.poll(() =>
			sql(
				`select count(*) from public.emails where event = 'VerifyEmail' and email = '${newEmail}';`
			)
		)
		.toBe('1');
	expect(sql(`select email from public.scholars where id = '${R4.id}';`)).toBe(R4.email);

	// Re-entering the address already on file sends nothing (no verification, no email).
	await page.getByTestId('scholar-email-toggle').click();
	await field.fill(`  ${R4.email}  `);
	await field.blur();
	await expect(page.getByTestId('verify-email-unchanged')).toBeVisible();
	expect(
		sql(`select count(*) from public.emails where event = 'VerifyEmail' and email = '${R4.email}';`)
	).toBe('0');
});
