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

	async signIn(email: string, password: string | undefined) {
		if (password === undefined) {
			const { error } = await this.client.auth.signInWithOtp({
				email
			});
			return error;
		} else {
			const { data, error } = await this.client.auth.verifyOtp({
				email,
				token: password,
				type: 'email'
			});
			return error ? error : (data.user?.id ?? null);
		}
	}
}

const AuthSymbol = Symbol('auth');

export function setAuth(auth: () => SupabaseAuth) {
	setContext(AuthSymbol, auth);
}

export function getAuth(): () => SupabaseAuth {
	return getContext<() => SupabaseAuth>(AuthSymbol);
}
