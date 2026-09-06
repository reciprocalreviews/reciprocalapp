/**
 * Whether a route requires an authenticated session. Public routes — the landing page,
 * login, the marketing pages, and the email-verification link (followed while logged out)
 * — return false; everything else returns true. A leading `/<lang>` locale prefix is
 * ignored. Used to decide whether a lost/expired session should bounce the scholar to the
 * login page (see src/routes/+layout.ts and +layout.svelte).
 */
export function requiresAuth(pathname: string): boolean {
	const path = pathname.replace(/^\/[a-z]{2}(?=\/|$)/, '') || '/';
	if (path === '/') return false;
	// Every page the footer links to belongs here. `/help`, `/contact` and `/brand` were
	// missing, so a visitor holding a stale or revoked cookie was redirected away from
	// them — including from `/contact`, the support front door, which is precisely where
	// someone whose session has broken needs to arrive. The omission was invisible for
	// `/help` while it was prerendered, because the redirect below never ran for a page
	// served from the filesystem; it is rendered per request now.
	const publicPrefixes = [
		'/login',
		'/about',
		'/help',
		'/contact',
		'/brand',
		'/terms',
		'/updates',
		'/verify'
	];
	return !publicPrefixes.some((prefix) => path === prefix || path.startsWith(`${prefix}/`));
}
