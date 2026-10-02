import { safeNext } from '$lib/auth/next';
import { redirect } from '@sveltejs/kit';
import type { PageLoad } from './$types';

/**
 * Someone already signed in has nothing to do here, so they go straight on: to `next` when a
 * link carried one, otherwise to their own profile. Done in the load rather than only in the
 * page's effect so the login page never paints first, which is what lets every email button
 * route through /login (#191) without costing a signed-in reader anything.
 */
export const load: PageLoad = async ({ parent, url }) => {
	const { claims } = await parent();
	if (claims?.sub)
		redirect(303, safeNext(url.searchParams.get('next')) ?? `/scholar/${claims.sub}`);
};
