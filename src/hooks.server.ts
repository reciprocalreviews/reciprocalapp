import { createServerClient } from '@supabase/ssr';
import { type Handle } from '@sveltejs/kit';

import { hasAuthCookie } from '$lib/auth/hasAuthCookie';

import { PUBLIC_SUPABASE_PUBLISHABLE_KEY, PUBLIC_SUPABASE_URL } from '$env/static/public';

/**
 * Routes whose HTML is the same for every anonymous visitor, and which are therefore
 * worth letting the CDN serve without invoking this function at all.
 *
 * These four used to be `prerender = true`. That made them genuinely free, but it also
 * ran `+layout.server.ts` at build time against a request with no cookies, so `cookies:
 * []` was baked into the shipped payload and a signed-in scholar landed on the anonymous
 * header until hydration flipped it. They are rendered per request now, and cached per
 * request instead — anonymous visitors still come off the CDN, and a signed-in scholar
 * gets a correct header in the first byte.
 *
 * Matched on `event.route.id` rather than the pathname because `[[lang]]` is optional and
 * unconstrained: `/terms`, `/en/terms` and `/anything/terms` all resolve to
 * `/[[lang]]/terms`.
 */
const PUBLICLY_CACHEABLE = new Set(['/', '/[[lang]]/terms', '/[[lang]]/updates', '/[[lang]]/help']);

export const handle: Handle = async ({ event, resolve }) => {
	/** Filter out annoying Chrome logs */
	if (event.url.pathname.startsWith('/.well-known/appspecific/com.chrome.devtools')) {
		return new Response(null, { status: 204 }); // Return empty response with 204 No Content
	}

	/**
	 * Creates a Supabase client specific to this server request.
	 *
	 * The Supabase client gets the Auth token from the request cookies.
	 */
	event.locals.supabase = createServerClient(PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_PUBLISHABLE_KEY, {
		cookies: {
			getAll: () => event.cookies.getAll(),
			/**
			 * Note: You have to add the `path` variable to the
			 * set and remove method due to sveltekit's cookie API
			 * requiring this to be set, setting the path to `/`
			 * will replicate previous/standard behaviour (https://kit.svelte.dev/docs/types#public-types-cookies)
			 */
			setAll: (cookiesToSet, headers) => {
				// Supabase can refresh a token asynchronously — `_notifyAllSubscribers` resolving
				// after the handler returned — and SvelteKit throws if cookies are set once the
				// response has been generated. That throw surfaces inside a promise nobody
				// awaits, so it becomes an unhandled rejection and takes the whole Node process
				// down; in `vite preview` that kills the server outright. There is nothing to do
				// about a session written too late: the response is already on its way, and the
				// client refreshes again on the next request. So swallow it rather than crash.
				try {
					cookiesToSet.forEach(({ name, value, options }) => {
						event.cookies.set(name, value, { ...options, path: '/' });
					});
					if (Object.keys(headers).length > 0) {
						event.setHeaders(headers);
					}
				} catch {
					// Response already sent; see above.
				}
			}
		}
	});

	const response = await resolve(event, {
		filterSerializedResponseHeaders(name) {
			/**
			 * Supabase libraries use the `content-range` and `x-supabase-api-version`
			 * headers, so we need to tell SvelteKit to pass it through.
			 */
			return name === 'content-range' || name === 'x-supabase-api-version';
		}
	});

	/**
	 * Decide whether this response may be shared.
	 *
	 * This lives here, rather than in a `load` calling `setHeaders`, because only here is
	 * the response finished: kit applies `setHeaders` values and then `Set-Cookie` inside
	 * the `resolve()` we just awaited, so a load cannot see a cookie it is about to set,
	 * and this can. That matters — `+layout.server.ts` serializes the real auth cookies,
	 * JWT included, into the HTML and into `__data.json`, so marking an authenticated
	 * response public would hand one scholar's session to whoever asked next.
	 *
	 * Hence three conditions, all required, for `public`: a route on the list, no session
	 * cookie on the request, and no cookie being set on the response.
	 */
	if (PUBLICLY_CACHEABLE.has(event.route.id ?? '')) {
		// `Vary: cookie` on both branches, so a request carrying cookies can never match
		// the entry cached for requests carrying none. Appended rather than overwritten,
		// so a `Vary` kit set for its own reasons survives.
		const vary = response.headers.get('vary');
		if (!vary?.toLowerCase().includes('cookie'))
			response.headers.set('vary', vary ? `${vary}, cookie` : 'cookie');

		const shareable = !hasAuthCookie(event.cookies.getAll()) && !response.headers.has('set-cookie');

		response.headers.set(
			'cache-control',
			shareable
				? // `max-age=0` deliberately alongside `s-maxage`: the shared cache may keep
					// this, the browser may not. A visitor who signs in must not be served the
					// anonymous page out of their own disk cache, where no request happens and
					// nothing can correct it. `s-maxage` starts conservative — raise it once the
					// hit rate has been measured.
					'public, max-age=0, s-maxage=3600, stale-while-revalidate=86400'
				: 'private, no-store'
		);
	}

	return response;
};
