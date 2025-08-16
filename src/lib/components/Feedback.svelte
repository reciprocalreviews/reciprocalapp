<script lang="ts">
	import type { Snippet } from 'svelte';

	const {
		error = false,
		inline = true,
		children
	}: { error?: boolean; inline?: boolean; children: Snippet } = $props();
</script>

{#if inline}
	<p class={['inline', { error }]}>{@render children()}</p>
{:else}
	<p class={{ error }}>{@render children()}</p>
{/if}

<style>
	p {
		margin-top: 0;
		background: var(--salient-color);
		color: var(--background-color);
		font-size: var(--small-font-size);
		padding: var(--spacing);
		border-radius: var(--roundedness);
	}

	p :global(a) {
		color: var(--background-color);
		text-decoration: underline;
	}

	.inline {
		display: inline-block;
		align-self: flex-start;
	}

	.error {
		background: var(--error-color);
		font-weight: normal;
	}
</style>
