/**
 * Caller authorization for the edge functions.
 *
 * Both functions here are invoked only by the database — `resend` from the
 * `send_on_email_insert` trigger, `remind` from the `remind-daily` cron job — never from a
 * browser. `resend` takes its recipient and (when rendering is delegated) its arguments
 * from the caller, so an unauthenticated endpoint would be an open relay for mail branded
 * as notifications@reciprocal.reviews.
 *
 * The check is a direct one: **did the caller present one of this project's server-side
 * secret keys?** Publishable/anon keys are public, so only a secret key proves the caller
 * is the server. This deliberately does not inspect JWT claims. The previous version
 * decoded the token and required `role === 'service_role'`, which only works for the
 * legacy JWT-shaped API keys — the newer `sb_secret_...` keys are opaque strings with no
 * payload to decode, so a claims check breaks the moment a project migrates. Comparing
 * against the injected key works for both formats.
 *
 * `verify_jwt` is OFF for these functions (see the `[functions.*]` blocks in
 * supabase/config.toml) because the platform gate rejects the new API keys outright. That
 * makes this the ONLY gate, so it fails closed: if no secret key is configured in the
 * environment, every request is refused rather than waved through.
 */

/** Constant-time comparison of two equal-length byte arrays. */
function timingSafeEqual(a: Uint8Array, b: Uint8Array): boolean {
	if (a.length !== b.length) return false;
	let difference = 0;
	for (let i = 0; i < a.length; i++) difference |= a[i] ^ b[i];
	return difference === 0;
}

/** SHA-256 digest, so comparisons are over fixed-width input and leak no length. */
async function digest(value: string): Promise<Uint8Array> {
	return new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value)));
}

/**
 * Every server-side secret key this project accepts.
 *
 * Hosted runtimes inject these automatically, so a deployed project needs no extra
 * configuration: `SUPABASE_SECRET_KEYS` is the new-format injection and is a JSON
 * *dictionary* keyed by key name rather than a bare string, and `SUPABASE_SERVICE_ROLE_KEY`
 * is the legacy injection, present until legacy keys are removed. Reading both means the
 * project can migrate key formats without a flag day where the database and the functions
 * disagree about which key is valid.
 *
 * `EDGE_SECRET_KEY` exists for LOCAL development only. The Supabase CLI refuses to pass
 * any `--env-file` entry whose name begins with `SUPABASE_` ("Env name cannot start with
 * SUPABASE_, skipping"), and it does not inject the hosted variables into
 * `supabase functions serve`, so local runs need a non-reserved name. It seeds the
 * `secret_key` vault entry too (see [db.vault] in supabase/config.toml), which is what
 * keeps the local database and the local functions presenting/accepting the same value.
 */
function acceptedKeys(): string[] {
	const keys: string[] = [];

	const dictionary = Deno.env.get('SUPABASE_SECRET_KEYS');
	if (dictionary) {
		try {
			const parsed = JSON.parse(dictionary);
			if (parsed && typeof parsed === 'object') {
				for (const value of Object.values(parsed)) if (typeof value === 'string') keys.push(value);
			}
		} catch {
			// A malformed dictionary contributes no keys; it must not make us fail open.
		}
	}

	for (const name of ['SUPABASE_SERVICE_ROLE_KEY', 'EDGE_SECRET_KEY']) {
		const value = Deno.env.get(name);
		if (value) keys.push(value);
	}

	return keys.filter((key) => key.trim().length > 0);
}

/** The key the caller presented, from either header convention. */
function presentedKey(request: Request): string {
	// New-format keys are sent on `apikey`; they are rejected on `Authorization: Bearer`
	// because that header is reserved for JWTs. Legacy service-role JWTs are conventionally
	// sent as a bearer token. Accept either so both formats work.
	const apikey = request.headers.get('apikey');
	if (apikey && apikey.trim().length > 0) return apikey.trim();
	return (request.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '').trim();
}

/**
 * Return a 403 Response when the caller did not present a server-side secret key, or null
 * when authorized. Callers should return the Response immediately when it is non-null.
 * `headers` carries the CORS headers the caller uses on its other responses.
 */
export async function requireSecretKey(
	request: Request,
	headers: Record<string, string> = {}
): Promise<Response | null> {
	const forbidden = () =>
		new Response(JSON.stringify({ error: 'Forbidden' }), {
			status: 403,
			headers: { ...headers, 'Content-Type': 'application/json' }
		});

	const presented = presentedKey(request);
	const accepted = acceptedKeys();
	// Fail closed on a missing key and on a project with no secret key configured at all.
	if (presented.length === 0 || accepted.length === 0) return forbidden();

	const presentedDigest = await digest(presented);
	for (const key of accepted) {
		if (timingSafeEqual(presentedDigest, await digest(key))) return null;
	}
	return forbidden();
}
