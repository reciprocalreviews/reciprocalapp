/**
 * The landing page loads no data of its own — it renders locale strings and nothing
 * else — so it can be served from the edge with no function invocation at all.
 *
 * The trade is in the header: `Nav` renders signed-in state from the root layout's
 * data, and prerendering bakes in `cookies: []`, so a signed-in scholar arriving here
 * sees the anonymous header until hydration re-runs `+layout.ts` and it flips to their
 * profile and balance. Auth itself is unaffected — `createBrowserClient` reads the real
 * cookies from `document.cookie`; only the server client uses `data.cookies`. Anything
 * added to this page that must be correct on first paint for a signed-in scholar has to
 * remove this line.
 */
export const prerender = true;
