import { redirect } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

// ORCID OIDC redirect target. `signInWithOAuth` sends the browser to ORCID (via
// Supabase), which returns here with a PKCE `code`. hooks.server.ts builds
// `locals.supabase` with cookie get/set, and @supabase/ssr stored the PKCE verifier in
// a cookie during signInWithOAuth, so exchangeCodeForSession here persists the session
// cookie. This route lives outside [[lang]] so its URL is stable for the provider
// allow-list. See src/routes/Auth.svelte.ts (signInWithORCID).
export const GET: RequestHandler = async ({ url, locals }) => {
	const code = url.searchParams.get('code');
	if (code) {
		const { data, error } = await locals.supabase.auth.exchangeCodeForSession(code);
		if (!error && data.user?.id) {
			// The handle_new_scholar trigger creates the scholar row on first sign-in;
			// send them to their profile (a new scholar has no verified email yet, so the
			// layout banner will prompt them to add one — see Banners.svelte).
			redirect(303, `/scholar/${data.user.id}`);
		}
	}
	redirect(303, '/login?error=orcid');
};
