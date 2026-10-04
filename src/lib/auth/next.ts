/** Where to go after signing in, carried by `/login?next=…` -- used by the notification-settings
 * link in email footers, which has to pass through sign-in because the controls only render
 * on a scholar's own profile while signed in.
 *
 * A return path is an open-redirect waiting to happen, so only a path on this site is
 * accepted: it starts with a single `/` (not `//` or `/\`, which browsers treat as another
 * host), contains no whitespace or control characters, and resolves to the same origin.
 * Anything else is dropped, and the caller falls back to the scholar's own profile. */
export function safeNext(value: string | null | undefined): string | null {
	if (!value || value.length > 512) return null;
	if (!value.startsWith('/') || value.startsWith('//') || value.startsWith('/\\')) return null;
	if (/[\s\u0000-\u001f\u007f]/.test(value)) return null;
	try {
		const base = 'https://rr.invalid';
		const url = new URL(value, base);
		if (url.origin !== base) return null;
		return url.pathname + url.search + url.hash;
	} catch {
		return null;
	}
}

/** The cookie that carries `next` across the ORCID round trip, which returns to
 * /auth/callback rather than to /login. A cookie rather than a query parameter on the
 * callback URL, because the identity provider only accepts redirect URLs it has registered. */
export const NEXT_COOKIE = 'rr_next';

/** A link to sign in that comes back to `url` afterwards -- for every "Log in" the app offers
 * and every redirect to the login page, so that someone who arrived from an email or a shared
 * link lands where it pointed rather than on their own profile (#191). Plain `/login` from the
 * landing page, which is no destination, and from the login page itself, so a return path
 * never nests inside another. */
export function loginHref(url: Pick<URL, 'pathname' | 'search' | 'hash'> | string): string {
	const { pathname, search, hash } =
		typeof url === 'string' ? new URL(url, 'https://rr.invalid') : url;
	const path = pathname.replace(/^\/[a-z]{2}(?=\/|$)/, '') || '/';
	if (path === '/' || path === '/login' || path.startsWith('/login/')) return '/login';
	const next = safeNext(pathname + search + hash);
	return next ? `/login?next=${encodeURIComponent(next)}` : '/login';
}
