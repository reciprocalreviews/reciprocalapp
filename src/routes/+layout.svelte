<script lang="ts" context="module">
	const AuthContext = Symbol('auth');

	export function getAuth() {
		return getContext<Auth>(AuthContext);
	}
</script>

<script lang="ts">
	import { dev } from '$app/environment';
	import { goto } from '$app/navigation';
	import Header from '$lib/components/Header.svelte';
	import { AuthSymbol, DatabaseSymbol } from '$lib/Context';
	import MockDatabase from '$lib/data/MockDatabase';
	import { getContext, onMount, setContext, type Snippet } from 'svelte';
	import { invalidate } from '$app/navigation';
	import type { Session, SupabaseClient, User } from '@supabase/supabase-js';
	import Auth from './Auth.svelte';

	let {
		data,
		children
	}: { data: { session: Session; supabase: SupabaseClient }; children: Snippet } = $props();

	let auth = new Auth(data.supabase);

	/** Always go home in production, pre-release */
	onMount(() => {
		if (!dev) goto('/');

		// Listen to auth stage changes and invalidate the auth context when they happen.
		const { data: response } = data.supabase.auth.onAuthStateChange((_, newSession) => {
			auth.setUser(newSession?.user ?? null);
			if (newSession?.expires_at !== data.session?.expires_at) {
				invalidate('supabase:auth');
			}
		});

		return () => response.subscription.unsubscribe();
	});

	/** Set a database connection context for all to use. */
	setContext(DatabaseSymbol, new MockDatabase());

	/** Set an auth connection context for all to use */
	setContext(AuthSymbol, auth);

	setContext(AuthContext, auth);
</script>

{#if dev}
	<Header />
{/if}
{@render children()}
