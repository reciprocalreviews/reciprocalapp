<script lang="ts">
	import { goto } from '$app/navigation';
	import Header from '$lib/components/Header.svelte';
	import { onMount } from 'svelte';
	import { invalidate } from '$app/navigation';
	import type { AuthError, PostgrestError } from '@supabase/supabase-js';
	import { createAuthContext, getAuth } from './Auth.svelte';
	import { setDB } from '$lib/data/CRUD';
	import SupabaseCRUD from '$lib/data/SupabaseCRUD.svelte';
	import { getFeedback, removeError, type Level } from './feedback.svelte';
	import Button from '$lib/components/Button.svelte';
	import { enUS } from '../locale/Locale';
	import { PUBLIC_ENV } from '$env/static/public';
	import Feedback from '$lib/components/Feedback.svelte';
	import Footer from '$lib/components/Footer.svelte';

	let { data, children } = $props();

	// svelte-ignore state_referenced_locally
	createAuthContext(data.supabase, data.session);

	let crud = $derived(new SupabaseCRUD(data.supabase, enUS));

	// Set client side database cache.
	setDB(() => crud);

	const auth = getAuth();

	let feedback = $derived(getFeedback());

	const inProd = PUBLIC_ENV === 'prod';

	/** Always go home in production, pre-release */
	onMount(() => {
		if (inProd) goto('/');

		// Listen to auth stage changes and invalidate the auth context when they happen.
		const { data: response } = data.supabase.auth.onAuthStateChange((_, newSession) => {
			auth.setUser(newSession?.user ?? null);
			if (newSession?.expires_at !== data.session?.expires_at) {
				invalidate('supabase:auth');
			}
		});

		return () => response.subscription.unsubscribe();
	});
</script>

{#snippet MessageBox(
	message: string,
	level: Level,
	index: number,
	error: PostgrestError | AuthError | undefined
)}
	<div class="feedback {level}">
		<div>
			<span>{message}</span>
			{#if error}
				<div class="detail">{error.message}</div>
			{/if}
		</div>
		<Button action={() => removeError(index)} tip="Dismiss notification">𐄂</Button>
	</div>
{/snippet}

{#if PUBLIC_ENV === 'test'}
	<Feedback error inline={false}
		>This is a test environment for preview purposes. Data can be deleted at any time.</Feedback
	>
{/if}

{#if !inProd}
	<Header />
{/if}
<main>
	<section class="notifications" aria-live="assertive">
		{#each feedback as item, index}
			{@render MessageBox(item.message, item.level, index, item.error)}
		{/each}
	</section>
	{@render children()}
</main>
{#if !inProd}
	<Footer />
{/if}

<style>
	main {
		margin-block-start: var(--spacing);
		display: flex;
		flex-direction: column;
		gap: var(--spacing);
		padding: calc(2 * var(--spacing));
		margin: auto;
		max-width: var(--page-width);
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

	.detail {
		font-family: monospace;
		font-size: var(--small-font-size);
	}
</style>
