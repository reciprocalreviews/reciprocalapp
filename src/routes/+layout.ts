import type { Database } from '$data/database';
import type { ScholarRow } from '$data/types';
import { requiresAuth } from '$lib/auth/requiresAuth';
import SupabaseCRUD from '$lib/data/SupabaseCRUD.svelte';
import { PUBLIC_SUPABASE_PUBLISHABLE_KEY, PUBLIC_SUPABASE_URL } from '$env/static/public';
import { createBrowserClient, createServerClient, isBrowser } from '@supabase/ssr';
import { redirect } from '@sveltejs/kit';
import type { LayoutLoad } from './$types';

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
	const db = new SupabaseCRUD(supabase, data.locale);

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

	// If there's a user, return scholar
	if (userID) {
		const { data: scholarData } = await db.getScholarRow(userID);
		scholar = scholarData ?? null;
	} else scholar = null;

	return { claims, db, scholar, locale: data.locale };
};
