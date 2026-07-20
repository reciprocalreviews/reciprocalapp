import type { ScholarRow } from '$data/types';
import Authentication from '$lib/auth/Authentication';
import type { AuthError, SupabaseClient } from '@supabase/supabase-js';
import { getContext, setContext } from 'svelte';

/** Represents the current authenatication state from Supabase. */
export default class SupabaseAuth extends Authentication<ScholarRow, AuthError> {
	user = $state<ScholarRow | null>(null);
	private client: SupabaseClient;

	constructor(supabase: SupabaseClient, scholar: ScholarRow | null) {
		super();
		this.client = supabase;
		this.user = scholar;
	}

	setUser(user: ScholarRow | null) {
		this.user = user;
	}

	isAuthenticated() {
		return this.user !== null;
	}

	getUserID(): string | null {
		return this.user?.id ?? null;
	}

	async signOut() {
		const { error } = await this.client.auth.signOut();
		return error;
	}

	async signInWithORCID(redirectTo: string) {
		// `custom:orcid` is the custom OIDC provider configured in the hosted Supabase
		// Dashboard (Authentication → Providers → New Provider → Auto-discovery (OIDC),
		// with the bare issuer URL https://orcid.org — or https://sandbox.orcid.org in
		// staging — and email_optional = true). Supabase requires custom provider
		// identifiers to carry the `custom:` prefix; a bare 'orcid' is rejected at
		// /auth/v1/authorize. Do not cast this string: `Provider` already admits
		// `custom:${string}`, so an unprefixed value is a type error rather than a
		// runtime failure that only appears in a hosted environment.
		//
		// We request only the `openid` scope — ORCID releases no email through OIDC on
		// any membership tier, so contact email is collected and verified in-app (#27).
		const { error } = await this.client.auth.signInWithOAuth({
			provider: 'custom:orcid',
			options: { redirectTo, scopes: 'openid' }
		});
		return error;
	}

	async signInWithPassword(email: string, password: string) {
		const { data, error } = await this.client.auth.signInWithPassword({ email, password });
		return error ? error : (data.user?.id ?? null);
	}

	async signInWithMockORCID(orcid: string, name: string) {
		// LOCAL/STAGING dev-only mock of an ORCID sign-in, so the new-account onboarding
		// flow can be seen without a real custom-OIDC round-trip (which can't run against
		// local Supabase). Never reachable in production — the login UI only offers this
		// off-prod. Locally, enable_signup is on and enable_confirmations is off, so a plain
		// signUp returns a live session immediately and fires the handle_new_scholar trigger,
		// which reads the ORCID iD/name from user metadata (`sub`/`orcid`/`name`) and creates
		// the scholar row with a null contact email — exactly like a real first sign-in. The
		// throwaway email is only the auth identity; handle_new_scholar ignores it.
		const email = `${orcid.replace(/-/g, '')}@orcid.example`;
		const password = 'password';
		const { data, error } = await this.client.auth.signUp({
			email,
			password,
			options: { data: { sub: orcid, orcid, name } }
		});
		if (data.session && data.user) return data.user.id;
		// A reused iD is an existing mock user (signUp returns no session): sign in to it,
		// exercising the returning-scholar path instead of onboarding.
		const signIn = await this.client.auth.signInWithPassword({ email, password });
		if (signIn.error) return error ?? signIn.error;
		return signIn.data.user?.id ?? null;
	}
}

const AuthSymbol = Symbol('auth');

export function setAuth(auth: () => SupabaseAuth) {
	setContext(AuthSymbol, auth);
}

export function getAuth(): () => SupabaseAuth {
	return getContext<() => SupabaseAuth>(AuthSymbol);
}
