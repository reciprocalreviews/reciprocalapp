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
		border-left: calc(var(--thick-border-width) * 2) solid var(--salient-color);
		background: var(--salient-color-faded);
		padding: calc(var(--spacing) / 3) calc(var(--spacing));
		font-size: var(--small-font-size);
		border-top-right-radius: var(--roundedness);
		border-bottom-right-radius: var(--roundedness);
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
		border-left-color: var(--error-color);
	}
</style>
