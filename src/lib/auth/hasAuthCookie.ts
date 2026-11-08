/**
 * Whether a request carries a Supabase session cookie.
 *
 * A prefix match, not an exact name, for two reasons: the cookie is
 * `sb-<projectref>-auth-token`, and the project ref differs between staging and
 * production; and Supabase splits a session too large for one cookie into
 * `…-auth-token.0`, `…-auth-token.1`, so the unsuffixed name may never appear.
 *
 * This asks only whether a session is *claimed*, never whether it is valid — an expired
 * or revoked token still counts. That is exactly what the caching decision in
 * `hooks.server.ts` needs: a request bearing any cookie must not be served, or fill, the
 * shared anonymous cache entry, whatever the token turns out to be worth.
 */
export function hasAuthCookie(cookies: { name: string }[]): boolean {
	return cookies.some((cookie) => /^sb-.*-auth-token/.test(cookie.name));
}
