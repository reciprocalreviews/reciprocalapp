import { type BrowserContext, type Page } from '@playwright/test';

// Relative, not the `$lib` alias: this module is loaded by Playwright through
// Node, not through Vite, so nothing is around to resolve the alias. Playwright
// maps it from the `paths` in `.svelte-kit/tsconfig.json`, which only exists
// after `svelte-kit sync` — so on a fresh checkout the whole suite failed to
// collect. See ARCHITECTURE.md § Testing.
export { SEED_PASSWORD } from '../lib/auth/devPassword';
import { SEED_PASSWORD } from '../lib/auth/devPassword';

/**
 * Navigate to the login page and wait until its form is actually usable.
 *
 * Two things make a bare `page.goto('/login')` unreliable here, and both showed up
 * as the same intermittent `net::ERR_ABORTED`:
 *
 * 1. The login page can supersede its own navigation. The root layout subscribes
 *    to `onAuthStateChange` and redirects on a `SIGNED_OUT` event; when that fires
 *    while the page is still loading, the client-side navigation cancels the one
 *    Playwright is awaiting, and an aborted navigation is reported as a failure
 *    rather than the redirect it actually is. Retrying once absorbs it.
 * 2. `waitUntil: 'load'` says the document finished, not that Svelte has hydrated
 *    and wired the form's handlers. Waiting for the field is the real signal — the
 *    same reason ARCHITECTURE.md prescribes a hydration barrier before any Svelte
 *    interaction.
 *
 * Worth keeping rather than raising `retries`: the config sets `retries: 0` locally
 * on purpose, so flakes get investigated instead of retried away. This removes the
 * flake at its source, which keeps that policy honest.
 */
async function gotoLogin(page: Page) {
	const attempts = 2;
	for (let attempt = 1; ; attempt++) {
		try {
			await page.goto('/login', { waitUntil: 'domcontentloaded' });
			break;
		} catch (error) {
			const aborted = error instanceof Error && error.message.includes('ERR_ABORTED');
			if (!aborted || attempt === attempts) throw error;
		}
	}
	await page.getByTestId('email-input').waitFor({ state: 'visible' });
}

/**
 * Log in for tests using the local-only email+password grant.
 *
 * Production authenticates exclusively with ORCID (custom OIDC), which cannot be
 * configured in local Supabase, so the login page renders a dev-only password form
 * off-production (see src/routes/[[lang]]/login/+page.svelte). Tests drive that form.
 * `context` is accepted for signature compatibility with callers but is unused.
 */
export async function login(email: string, page: Page, _context?: BrowserContext) {
	await gotoLogin(page);
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
	// Via gotoLogin: signing out is precisely when the auth-change listener fires,
	// so this is the navigation most likely to be superseded and aborted.
	await gotoLogin(page);
}
