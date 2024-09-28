<script lang="ts">
	import { dev } from '$app/environment';
	import { goto } from '$app/navigation';
	import Header from '$lib/components/Header.svelte';
	import { onMount, setContext, type Snippet } from 'svelte';
	import { invalidate } from '$app/navigation';
	import type { Session, SupabaseClient } from '@supabase/supabase-js';
	import { createAuthContext, getAuth } from './Auth.svelte';
	import { setDB } from '$lib/data/Database';
	import SupabaseDB from '$lib/data/SupabaseDatabase.svelte';

	let {
		data,
		children
	}: { data: { session: Session; supabase: SupabaseClient }; children: Snippet } = $props();

	createAuthContext(data.supabase);
	const auth = getAuth();

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

	// Set client side database cache.
	setDB(new SupabaseDB(data.supabase));
</script>

{#if dev}
	<Header />
{/if}
<main>
	{@render children()}
</main>

<style>
	main {
		margin-block-start: var(--spacing);
	}
</style>
