import type { PageServerLoad } from './$types';

// Consume the contact-email verification token (#27). Done in a SERVER load, called
// through the anon-callable verify_email RPC on the per-request Supabase client, so the
// token is redeemed on the initial visit rather than again on every client-side
// re-run — a universal load would re-run on hydration and on invalidate('supabase:auth').
// The RPC commits the candidate into scholars.email on success. It deliberately does NOT
// delete the request: verification is idempotent within the 15-minute window, so a link
// that gets fetched more than once (an email security scanner, a prefetch) still reports
// 'verified' rather than a misleading 'invalid'.
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
