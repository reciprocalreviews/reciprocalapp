import type { PendingEmailVerification } from '$lib/data/CRUD';
import type { PageServerLoad } from './$types';

// Consume the contact-email verification token (#27). Done in a SERVER load, called
// through the anon-callable verify_email RPC on the per-request Supabase client, so the
// token is redeemed on the initial visit rather than again on every client-side
// re-run — a universal load would re-run on hydration and on invalidate('supabase:auth').
// The RPC commits the candidate into scholars.email on success. It deliberately does NOT
// delete the request: verification is idempotent within the 24-hour window, so a link
// that gets fetched more than once (an email security scanner, a prefetch) still reports
// 'verified' rather than a misleading 'invalid'.
export const load: PageServerLoad = async ({ params, locals }) => {
	const { data, error } = await locals.supabase.rpc('verify_email', { _token: params.token });
	if (error) {
		console.error('verify_email failed', error);
		return { status: 'error' as const, pending: null };
	}
	const result = (data ?? {}) as { status?: string; email?: string };
	const status = (result.status ?? 'invalid') as 'verified' | 'expired' | 'invalid';

	// An expired link is the one place a one-click resend belongs, and the resend needs to
	// know which address is pending. Asked here rather than in the browser so it arrives in
	// the first byte, and only for 'expired' — the other outcomes have nothing to resend.
	//
	// A caller with no session cannot execute this RPC at all (EXECUTE is revoked from
	// anon), so its refusal IS the signed-out answer. That saves plumbing a session check
	// into a route that is deliberately exempt from the auth redirect, and it fails the
	// safe way: no session, no pending state, no resend button.
	let pending: PendingEmailVerification | null = null;
	if (status === 'expired') {
		const { data: pendingData } = await locals.supabase.rpc('pending_email_verification');
		pending = (pendingData as PendingEmailVerification | null) ?? null;
	}

	return { status, email: result.email ?? null, pending };
};
