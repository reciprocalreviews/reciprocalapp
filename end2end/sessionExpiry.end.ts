import { test, expect } from '@playwright/test';
import { login } from '../src/routes/login';
import { SEED } from './test-utils';

// Session-expiry handling: a dead session on an authenticated page should send the scholar
// to login rather than leaving them to hit cryptic RLS/permission errors. r3 is otherwise
// unreferenced by the suite.
const R3 = SEED.scholars.r3;

test('a dead session on an authenticated page redirects to login', async ({ page, context }) => {
	test.setTimeout(60_000);

	await login(R3.email, page, context);
	await page.goto(`/scholar/${R3.id}`);
	await expect(page).toHaveURL(new RegExp(`/scholar/${R3.id}`));

	// Simulate the session dying: mark the stored session expired and give it a bogus refresh
	// token so it can't be silently refreshed — the state you land in after the local DB is
	// reset, or after the token's 1h lifetime lapses with the refresh token revoked. The auth
	// cookie is the @supabase/ssr `base64-<json>` session blob; keeping the cookie present is
	// what distinguishes an expired session from an anonymous visit.
	const cookies = await context.cookies();
	const auth = cookies.find((c) => c.name.includes('auth-token'));
	if (!auth) throw new Error('no supabase auth cookie found');
	const session = JSON.parse(
		Buffer.from(auth.value.replace(/^base64-/, ''), 'base64url').toString('utf8')
	);
	session.expires_at = Math.floor(Date.now() / 1000) - 3600;
	session.expires_in = 0;
	session.refresh_token = 'invalid';
	await context.addCookies([
		{ ...auth, value: `base64-${Buffer.from(JSON.stringify(session)).toString('base64url')}` }
	]);

	// Revisiting an authenticated page now bounces to login (the layout guard in
	// src/routes/+layout.ts), instead of rendering an authenticated page whose writes fail.
	await page.goto(`/scholar/${R3.id}`);
	await page.waitForURL(/\/login(\?|$)/);
});

test('an anonymous visitor can still view a public scholar profile', async ({ page }) => {
	// No auth cookie → not treated as an expired session → no redirect.
	await page.goto(`/scholar/${R3.id}`);
	await expect(page).toHaveURL(new RegExp(`/scholar/${R3.id}`));
});
