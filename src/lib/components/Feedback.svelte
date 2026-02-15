<script lang="ts">
	import type { Snippet } from 'svelte';

	const {
		error = false,
		inline = true,
		children,
		testid
	}: { error?: boolean; inline?: boolean; children: Snippet; testid?: string } = $props();
</script>

{#if inline}
	<span class={['feedback', 'inline', { error }]} data-testid={testid}>{@render children()}</span>
{:else}
	<p class={['feedback', { error }]} data-testid={testid}>{@render children()}</p>
{/if}

<style>
	p,
	span {
		border-left: calc(var(--thick-border-width) * 2) solid var(--salient-color);
		background: var(--salient-color-faded);
		padding: var(--spacing-half);
		font-size: var(--small-font-size);
		border-top-right-radius: var(--roundedness);
		border-bottom-right-radius: var(--roundedness);
		border-radius: var(--roundedness);
	}

	p {
		margin-top: 0;
	}

	.inline {
		display: inline-block;
		align-self: flex-start;
	}

	.error {
		border-left-color: var(--error-color);
		background: var(--error-color-faded);
	}
</style>
