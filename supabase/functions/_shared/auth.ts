/**
 * Caller authorization for the edge functions.
 *
 * Both functions here are invoked only by the database — `resend` from the
 * `send_on_email_insert` trigger, `remind` from the `remind-daily` cron job — never
 * from a browser. The platform's `verify_jwt` gate (see the `[functions.*]` blocks in
 * supabase/config.toml) checks the JWT signature before the handler runs, but it
 * accepts ANY valid project JWT, including the anon key that ships in the client
 * bundle. Signature verification alone therefore leaves these endpoints reachable by
 * anyone who reads the published key; the `role` claim is what actually restricts them
 * to server-side callers.
 *
 * We decode the payload without re-verifying the signature because `verify_jwt` has
 * already done that upstream — this check is about *which* authenticated caller it is,
 * not whether the token is genuine. (Local `supabase functions serve` runs with
 * --no-verify-jwt, so locally the signature is unchecked and this claim check is the
 * only gate; that is acceptable for a stack bound to localhost, and it is why the check
 * lives in the handler rather than relying on config alone.)
 */

/** Decode a JWT payload's `role` claim, or null if the token is malformed. */
function roleOf(token: string): string | null {
	const segments = token.split('.');
	if (segments.length !== 3) return null;
	try {
		const base64 = segments[1].replace(/-/g, '+').replace(/_/g, '/');
		const padded = base64.padEnd(base64.length + ((4 - (base64.length % 4)) % 4), '=');
		const claims = JSON.parse(atob(padded));
		return typeof claims?.role === 'string' ? claims.role : null;
	} catch {
		return null;
	}
}

/**
 * Return a 403 Response when the request is not from a `service_role` caller, or null
 * when it is authorized. Callers should return the Response immediately when non-null.
 * `headers` carries the CORS headers the caller uses on its other responses.
 */
export function requireServiceRole(
	request: Request,
	headers: Record<string, string> = {}
): Response | null {
	const token = (request.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '').trim();
	if (token.length === 0 || roleOf(token) !== 'service_role') {
		return new Response(JSON.stringify({ error: 'Forbidden' }), {
			status: 403,
			headers: { ...headers, 'Content-Type': 'application/json' }
		});
	}
	return null;
}
