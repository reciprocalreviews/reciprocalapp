/**
 * Make the browser's Supabase requests hash the same as the server's, so hydration reuses the
 * responses the server already inlined instead of asking for every one of them again.
 *
 * SvelteKit runs every universal `load` twice: on the server for the HTML, and again in the
 * browser before it mounts the app and wires up a single click handler. To keep the second run
 * off the network it inlines each server-side `fetch` response into the HTML as a
 * `<script data-sveltekit-fetched data-url=… data-hash=…>` and, in the browser, answers a
 * matching request from that script. "Matching" hashes the request's headers.
 *
 * `@supabase/ssr` stamps `X-Client-Info: supabase-ssr/<v> createServerClient` on the server
 * and `… createBrowserClient` in the browser — after any `global.headers` a caller passes, so
 * the option cannot equalize them. Every hash therefore missed, and a page such as a scholar's
 * profile re-ran all seventeen of its reads, in sequence, before a single button worked. The
 * server-rendered buttons look ready the whole time; a click in that window is silently
 * dropped, which is what a scholar who could not accept a role invitation was seeing.
 *
 * This wraps the `fetch` handed to both clients and pins the header to one value. It is SET
 * rather than deleted so Supabase's logs still attribute the traffic to this app.
 */

/** The one `X-Client-Info` both sides send. */
export const CLIENT_INFO = 'reciprocal-reviews';

/** A `fetch` whose requests carry the same `X-Client-Info` whichever side issues them. */
export function withStableClientInfo(fetcher: typeof fetch): typeof fetch {
	return (input, init) => {
		const headers = new Headers(init?.headers ?? (input instanceof Request ? input.headers : {}));
		headers.set('X-Client-Info', CLIENT_INFO);
		return fetcher(input, { ...init, headers });
	};
}
