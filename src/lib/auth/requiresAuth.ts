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
	const publicPrefixes = ['/login', '/about', '/terms', '/updates', '/verify'];
	return !publicPrefixes.some((prefix) => path === prefix || path.startsWith(`${prefix}/`));
}
