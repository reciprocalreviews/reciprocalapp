import type { PageServerLoad } from './$types';

// Consume the contact-email verification token (#27). Done in a SERVER load, called
// through the anon-callable verify_email RPC on the per-request Supabase client, so the
// single-use token is consumed exactly once on the initial visit — a universal load
// would re-run on hydration and on invalidate('supabase:auth') and burn the token. The
// RPC commits the candidate into scholars.email on success and deletes the request.
export const load: PageServerLoad = async ({ params, locals }) => {
	const { data, error } = await locals.supabase.rpc('verify_email', { _token: params.token });
	if (error) {
		console.error('verify_email failed', error);
		return { status: 'error' as const };
	}
	const result = (data ?? {}) as { status?: string; email?: string };
	const status = (result.status ?? 'invalid') as 'verified' | 'expired' | 'invalid';
	return { status, email: result.email ?? null };
};
