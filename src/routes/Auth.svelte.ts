import type { ScholarRow } from '$data/types';
import Authentication from '$lib/auth/Authentication';
import type { AuthError, Provider, SupabaseClient } from '@supabase/supabase-js';
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
		// 'orcid' is the custom OIDC provider slug configured in the hosted Supabase
		// Dashboard (Auth → Providers → Custom OIDC). We only request the `openid`
		// scope — ORCID does not release an email without a paid membership, so contact
		// email is collected and verified separately in-app (#27).
		const { error } = await this.client.auth.signInWithOAuth({
			provider: 'orcid' as Provider,
			options: { redirectTo, scopes: 'openid' }
		});
		return error;
	}

	async signInWithPassword(email: string, password: string) {
		const { data, error } = await this.client.auth.signInWithPassword({ email, password });
		return error ? error : (data.user?.id ?? null);
	}
}

const AuthSymbol = Symbol('auth');

export function setAuth(auth: () => SupabaseAuth) {
	setContext(AuthSymbol, auth);
}

export function getAuth(): () => SupabaseAuth {
	return getContext<() => SupabaseAuth>(AuthSymbol);
}
