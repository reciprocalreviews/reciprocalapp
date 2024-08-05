import type { SupabaseClient, User } from '@supabase/supabase-js';

export default class Auth {
	user = $state<User | null>(null);
	client: SupabaseClient;

	constructor(supabase: SupabaseClient) {
		this.client = supabase;
	}

	setUser(user: User | null) {
		this.user = user;
	}

	authenticated() {
		return this.user !== null;
	}

	signOut() {
		return this.client.auth.signOut();
	}

	async signIn(email: string) {
		const { error } = await this.client.auth.signInWithOtp({
			email
		});
		return error?.message;
	}
}
