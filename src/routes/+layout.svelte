<script lang="ts">
	import { dev } from '$app/environment';
	import { goto } from '$app/navigation';
	import Header from '$lib/components/Header.svelte';
	import { onMount, type Snippet } from 'svelte';
	import { invalidate } from '$app/navigation';
	import type { Session, SupabaseClient } from '@supabase/supabase-js';
	import { createAuthContext, getAuth } from './Auth.svelte';
	import { Errors, setDB } from '$lib/data/CRUD';
	import SupabaseCRUD from '$lib/data/SupabaseCRUD.svelte';
	import { getFeedback, removeError, type Level, isError } from './feedback.svelte';
	import Button from '$lib/components/Button.svelte';

	let {
		data,
		children
	}: { data: { session: Session; supabase: SupabaseClient }; children: Snippet } = $props();

	createAuthContext(data.supabase);
	const auth = getAuth();

	let feedback = $derived(getFeedback());

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
	setDB(new SupabaseCRUD(data.supabase));
</script>

{#snippet MessageBox(message: string, level: Level, index: number)}
	<div class="feedback {level}">
		<span>{message}</span>
		<Button action={() => removeError(index)} tip="Dismiss notification">𐄂</Button>
	</div>
{/snippet}

{#if dev}
	<Header />
{/if}
<main>
	<section class="notifications" aria-live="assertive">
		{#each feedback as feedback, index}{@render MessageBox(
				feedback.level === 'error' && isError(feedback.message)
					? Errors[feedback.message]
					: feedback.message,
				feedback.level,
				index
			)}{/each}
	</section>
	{@render children()}
</main>

<style>
	main {
		margin-block-start: var(--spacing);
	}

	.notifications {
		z-index: 2;
		position: fixed;
		top: var(--spacing);
		left: var(--spacing);
		right: var(--spacing);
		display: flex;
		flex-direction: column;
		gap: var(--spacing);
	}

	.feedback {
		display: flex;
		flex-direction: row;
		align-items: baseline;
		justify-content: space-between;
		color: var(--background-color);
		padding: var(--spacing);
		border: var(--border-width) solid var(--border-color);
		border-radius: var(--roundedness);
		background: var(--error-color);
		box-shadow: var(--spacing) var(--spacing) var(--spacing) var(--border-color);
	}

	.success {
		background: var(--salient-color);
	}

	.warning {
		background: var(--focus-color);
	}
</style>
