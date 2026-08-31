import type { Database } from '$data/database';
import type { ScholarRow } from '$data/types';
import { requiresAuth } from '$lib/auth/requiresAuth';
import SupabaseCRUD from '$lib/data/SupabaseCRUD.svelte';
import type { LocaleText } from '$lib/locales/Locale';
import en from '$locales/en.json';
import { PUBLIC_SUPABASE_PUBLISHABLE_KEY, PUBLIC_SUPABASE_URL } from '$env/static/public';
import { createBrowserClient, createServerClient, isBrowser } from '@supabase/ssr';
import { redirect } from '@sveltejs/kit';
import type { LayoutLoad } from './$types';

/**
 * The strings, bundled rather than fetched. `en.json` is the only locale file, and
 * the server load this replaced fell back to it for any other `params.lang` anyway,
 * so there is nothing to branch on yet — a second language becomes a branch here,
 * and should stay a static import so it remains part of node 0's preloaded graph.
 * A dynamic import would not be preloaded, and hydration awaits this load before
 * mounting, so it would buy an HTML payload at the cost of a serial round trip.
 */
const locale: LocaleText = en;

export const load: LayoutLoad = async ({ data, depends, fetch, url }) => {
	/**
	 * Declare a dependency so the layout can be invalidated, for example, on
	 * session refresh.
	 */
	depends('supabase:auth');

	const supabase = isBrowser()
		? createBrowserClient<Database, 'public'>(
				PUBLIC_SUPABASE_URL,
				PUBLIC_SUPABASE_PUBLISHABLE_KEY,
				{
					global: {
						fetch
					}
				}
			)
		: createServerClient<Database, 'public'>(PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_PUBLISHABLE_KEY, {
				global: {
					fetch
				},
				cookies: {
					getAll() {
						return data.cookies;
					},
					setAll() {
						// Cookie setting is handled by hooks.server.ts
					}
				}
			});

	// The single CRUD instance through which all reads and writes flow. The raw
	// `supabase` client is intentionally not returned as load data — it is only
	// reachable via `db.client`, the sanctioned escape hatch for auth and
	// realtime (#137).
	const db = new SupabaseCRUD(supabase, locale);

	let scholar: ScholarRow | null = null;

	/**
	 * `getClaims` validates the JWT signature locally (for asymmetric keys) once
	 * the relevant signing keys are available or cached, and returns the decoded
	 * claims. While an initial or periodic network request may be required to
	 * fetch or refresh keys, this is both faster and safer than `getSession`,
	 * which does not validate the JWT.
	 */
	const { data: claimsData, error } = await supabase.auth.getClaims();
	const claims = error ? null : claimsData?.claims;
	const userID = claims?.sub;

	// A Supabase auth cookie that's present but no longer validates (expired, or its refresh
	// token was revoked — e.g. after a local DB reset) means the session died. On a page that
	// requires authentication, send the scholar to login rather than rendering an
	// authenticated page where every write fails with a cryptic RLS/permission error. A
	// genuinely anonymous visitor has no auth cookie, so public browsing is unaffected. The
	// live case (token dying while the page is open) is handled by the SIGNED_OUT listener in
	// +layout.svelte.
	const hasAuthCookie = data.cookies.some((cookie) => /^sb-.*-auth-token/.test(cookie.name));
	if (!userID && hasAuthCookie && requiresAuth(url.pathname)) {
		redirect(302, '/login');
	}

	// If there's a user, return scholar, plus their total token balance for the
	// header. The count is loaded here rather than per page so the balance is
	// present on every route, and it refreshes for free: handle() calls
	// invalidateAll() after every successful write, which re-runs this load.
	let tokens = 0;
	if (userID) {
		// Together, not in sequence. The count doesn't read anything the row returns, and
		// this load re-runs on every client-side navigation (it reads `url.pathname`
		// below, so `uses.url` is set), which made the second round trip a per-navigation
		// cost paid at the scholar's own latency.
		const [{ data: scholarData, error: scholarError }, { data: tokenCount }] = await Promise.all([
			db.getScholarRow(userID),
			db.getScholarTokenCount(userID)
		]);
		scholar = scholarData ?? null;
		tokens = tokenCount;

		// A valid session with no scholar row is a dead end the app can neither show nor
		// escape. `isAuthenticated()` reads this row, so the person is rendered as
		// anonymous while genuinely signed in; the redirect above does not fire, because
		// it is gated on the absence of a user id and there is one; and signing in again
		// changes nothing, since the trigger that creates the row runs only when the
		// account is created. So repair it here and re-read.
		//
		// Only when the read actually SUCCEEDED. A failed read says nothing about whether
		// the row exists, and writing on the strength of an error is how a transient
		// outage turns into a second problem.
		//
		// The token count needs no re-read after a repair: `ensure_scholar` only inserts
		// a `scholars` row, and nothing can hold a token for a scholar that didn't exist,
		// so the count raced against the missing row is 0 and stays 0.
		if (scholar === null && scholarError === undefined) {
			const { data: outcome } = await db.ensureScholar();
			if (outcome === 'created') {
				const { data: repaired } = await db.getScholarRow(userID);
				scholar = repaired ?? null;
			}
		}
	} else scholar = null;

	return { claims, db, scholar, tokens, locale };
};
