/**
 * Whether the reader has dismissed the beta notice, and how that is remembered.
 *
 * The notice used to sit in the sticky header alongside the other banners, where it cost
 * every page a band of vertical space forever — it says the same thing on the thousandth
 * visit as on the first (#176). It lives in the footer now, and it can be put away.
 *
 * A cookie rather than `localStorage`, which is what makes this worth a module. Storage is
 * invisible to the server, so the banner would be in every server-rendered page and then
 * vanish at hydration — a flash on every load for exactly the people who already said they
 * were done with it. The root server load already returns every cookie, so a cookie is
 * known before the first byte and a dismissed notice is simply never rendered.
 */

/** The cookie's name. Prefixed, because it shares a namespace with Supabase's auth cookies. */
export const BETA_COOKIE = 'rr-beta-dismissed';

/** A year. The notice is not worth asking about again within one. */
const MAX_AGE_SECONDS = 60 * 60 * 24 * 365;

/**
 * Read the flag off the cookies the root server load collected.
 *
 * Deliberately takes the list `+layout.server.ts` already returns rather than reading
 * `cookies.get()` there: that load's whole job is to return the cookies and nothing else,
 * and deriving here costs nothing in the HTML or in the `__data.json` that every write
 * refetches.
 */
export function readBetaDismissed(cookies: { name: string; value: string }[]): boolean {
	return cookies.some((cookie) => cookie.name === BETA_COOKIE && cookie.value === '1');
}

/**
 * Remember the dismissal, from the browser.
 *
 * Client-side on purpose, and not merely because it avoids a round trip for a display
 * preference. A server write would put `Set-Cookie` on the response, and `hooks.server.ts`
 * treats the absence of that header as one of the conditions under which a page may be
 * cached by the shared CDN — so dismissing the notice would quietly make the landing page,
 * the terms, the updates and the help articles uncacheable for everyone. Those routes
 * already send `Vary: cookie`, so the cache simply keeps a second variant instead.
 *
 * `secure` only over https: local development is served over http, where a secure cookie
 * is silently dropped and the notice would come back on every reload.
 */
export function dismissBeta(): void {
	const secure = location.protocol === 'https:' ? '; secure' : '';
	document.cookie = `${BETA_COOKIE}=1; path=/; max-age=${MAX_AGE_SECONDS}; samesite=lax${secure}`;
}
