import type { LayoutServerLoad } from './$types';

export const load: LayoutServerLoad = async ({ cookies }) => {
	// Only the cookies. The locale used to be fetched here and returned as load
	// data, which cost an outbound HTTPS request from the serverless function back
	// to its own origin for 90KB of JSON on every render — server loads have no
	// filesystem read for `static/` under adapter-vercel, so kit's `fetch` falls
	// through to a real network call — and then serialized that 90KB into every
	// HTML response, and into every `__data.json` that `invalidateAll()` refetches
	// after every write. It is a static import in `+layout.ts` now: bundled on the
	// server, and an immutably-cached chunk in the browser.
	return {
		cookies: cookies.getAll()
	};
};
