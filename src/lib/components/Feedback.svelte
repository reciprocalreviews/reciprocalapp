<script lang="ts">
	import type { Snippet } from 'svelte';

	const {
		error = false,
		inline = true,
		children
	}: { error?: boolean; inline?: boolean; children: Snippet } = $props();
</script>

{#if inline}
	<span class={['inline', { error }]}>{@render children()}</span>
{:else}
	<p class={{ error }}>{@render children()}</p>
{/if}

<style>
	p,
	span {
		background: var(--salient-color);
		color: var(--background-color);
		padding: calc(var(--spacing) / 2);
		font-size: var(--small-font-size);
		border-radius: var(--roundedness);
	}

	p {
		margin-top: 0;
	}

	span :global(a),
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
