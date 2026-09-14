/**
 * Mint and VERIFY an ORCID Public API token, before it becomes a deployed secret.
 *
 * The verification is the point. A bad bearer token does not degrade — measured against the
 * live API, a read with no Authorization header returns 200 and the same read with a bad
 * bearer returns 401. The `orcid` edge function falls back to anonymous reads when that
 * happens (see supabase/functions/orcid/index.ts), so a wrong secret is survivable, but it
 * is much better caught here than inferred later from profiles that stopped updating.
 *
 * Usage:
 *   ORCID_CLIENT_ID=APP-... ORCID_CLIENT_SECRET=... node scripts/orcid-token.js
 *   node scripts/orcid-token.js APP-... <secret>
 *
 * Then put the printed token in Supabase → Edge Functions → Secrets as ORCID_PUBLIC_TOKEN,
 * PRODUCTION ONLY. Staging authenticates against the ORCID sandbox but the mirror always
 * reads production `pub.orcid.org`, so a sandbox token there would 401 every read — and
 * staging's sandbox iDs resolve to nothing on production anyway. See issue #173.
 */

const TOKEN_URL = 'https://orcid.org/oauth/token';
const API = 'https://pub.orcid.org/v3.0';
/** A real, stable, public record used only to prove the token actually reads something. */
const PROBE = '0000-0001-7461-4783';

const clientId = process.env.ORCID_CLIENT_ID ?? process.argv[2];
const clientSecret = process.env.ORCID_CLIENT_SECRET ?? process.argv[3];

if (!clientId || !clientSecret) {
	console.error('Usage: ORCID_CLIENT_ID=... ORCID_CLIENT_SECRET=... node scripts/orcid-token.js');
	console.error('   or: node scripts/orcid-token.js <client-id> <client-secret>');
	console.error('');
	console.error('Credentials come from orcid.org → your name → Developer Tools. Check the');
	console.error('Supabase Dashboard first (Authentication → Providers → custom:orcid):');
	console.error('ORCID issues one set per ORCID record, and sign-in already needed them.');
	process.exit(2);
}

/** Step 1: exchange the credentials for a token. */
const tokenResponse = await fetch(TOKEN_URL, {
	method: 'POST',
	headers: { Accept: 'application/json', 'Content-Type': 'application/x-www-form-urlencoded' },
	body: new URLSearchParams({
		client_id: clientId,
		client_secret: clientSecret,
		scope: '/read-public',
		grant_type: 'client_credentials'
	})
});

const payload = await tokenResponse.json().catch(() => null);

if (!tokenResponse.ok || !payload?.access_token) {
	console.error(`✗ ORCID refused the credentials (HTTP ${tokenResponse.status}).`);
	if (payload?.error) console.error(`  ${payload.error}: ${payload.error_description ?? ''}`);
	console.error('');
	console.error('  A sandbox client cannot mint a production token — sandbox credentials go');
	console.error('  to sandbox.orcid.org/oauth/token and only read pub.sandbox.orcid.org.');
	process.exit(1);
}

const token = payload.access_token;

/** Step 2: actually read something with it. Without this the script would happily print a
 * token that 401s on every real request, which is the failure it exists to prevent. */
const probe = await fetch(`${API}/${PROBE}/person`, {
	headers: { Accept: 'application/json', Authorization: `Bearer ${token}` }
});

if (!probe.ok) {
	console.error(`✗ The token was issued but cannot read the API (HTTP ${probe.status}).`);
	console.error('  Do NOT deploy it. Every ORCID read would fail this way.');
	process.exit(1);
}

const years = payload.expires_in ? (payload.expires_in / 60 / 60 / 24 / 365).toFixed(1) : '?';

console.log('✓ Token issued and verified against the live API.');
console.log('');
console.log(`  scope:   ${payload.scope ?? '/read-public'}`);
console.log(`  expires: ~${years} years from now`);
console.log('');
console.log(token);
console.log('');
console.log('  Set as ORCID_PUBLIC_TOKEN in Supabase → Edge Functions → Secrets.');
console.log('  PRODUCTION ONLY — see the note at the top of this file.');
