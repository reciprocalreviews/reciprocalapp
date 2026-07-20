import { createServerClient } from '@supabase/ssr';
import { type Handle } from '@sveltejs/kit';

import { PUBLIC_SUPABASE_PUBLISHABLE_KEY, PUBLIC_SUPABASE_URL } from '$env/static/public';

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

	return resolve(event, {
		filterSerializedResponseHeaders(name) {
			/**
			 * Supabase libraries use the `content-range` and `x-supabase-api-version`
			 * headers, so we need to tell SvelteKit to pass it through.
			 */
			return name === 'content-range' || name === 'x-supabase-api-version';
		}
	});
};
