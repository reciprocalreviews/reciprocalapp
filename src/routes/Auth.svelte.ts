import Authentication from '$lib/auth/Authentication';
import type { SupabaseClient, User } from '@supabase/supabase-js';
import { getContext, setContext } from 'svelte';

/** Represents the current authenatication state from Supabase. */
export default class SupabaseAuth extends Authentication<User> {
	private user = $state<User | null>(null);
	private client: SupabaseClient;

	constructor(supabase: SupabaseClient) {
		super();
		this.client = supabase;
	}

	setUser(user: User | null) {
		this.user = user;
	}

	isAuthenticated() {
		return this.user !== null;
	}

	getUserID(): string | null {
		return this.user?.id ?? null;
	}

	async signOut() {
		return await this.client.auth.signOut();
	}

	async signIn(email: string) {
		const { error } = await this.client.auth.signInWithOtp({
			email
		});
		return error?.message;
	}
}

const AuthSymbol = Symbol('auth');

export function createAuthContext(supabase: SupabaseClient) {
	setContext(AuthSymbol, new SupabaseAuth(supabase));
}

export function getAuth(): Authentication<User> {
	return getContext<SupabaseAuth>(AuthSymbol);
}
