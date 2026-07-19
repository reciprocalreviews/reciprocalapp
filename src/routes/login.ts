import { type BrowserContext, type Page } from '@playwright/test';

/** The shared password every seeded user has locally (see supabase/seed.sql). */
const SEED_PASSWORD = 'password';

/**
 * Log in for tests using the local-only email+password grant.
 *
 * Production authenticates exclusively with ORCID (custom OIDC), which cannot be
 * configured in local Supabase, so the login page renders a dev-only password form
 * off-production (see src/routes/[[lang]]/login/+page.svelte). Tests drive that form.
 * `context` is accepted for signature compatibility with callers but is unused.
 */
export async function login(email: string, page: Page, _context?: BrowserContext) {
	await page.goto('/login');
	await page.getByTestId('email-input').fill(email);
	await page.getByTestId('password-input').fill(SEED_PASSWORD);
	await page.getByTestId('password-submit').click();
	// Wait for the scholar page to be reached.
	await page.waitForURL(/\/scholar\/.+/);
}

/** A reusable function for logging out */
export async function logout(page: Page) {
	// Fire the in-app sign-out flow (clears Supabase state + triggers the
	// auth-change listener that invalidates the layout). We dispatch the click
	// event directly rather than using .click(): a success-feedback toast can
	// briefly overlap the logout button, which makes an actionability-checked
	// .click() time out (a common source of CI flakes). The handler fires
	// signOut() without awaiting it, so we also clear cookies directly — that
	// guarantees the session is gone even if the in-flight signOut request is
	// racing with our next navigation — then navigate to /login and wait for
	// the form to render.
	await page.getByTestId('logout-button').dispatchEvent('click');
	await page.context().clearCookies();
	await page.goto('/login');
	await page.getByTestId('email-input').waitFor({ state: 'visible' });
}
