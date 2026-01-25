<script lang="ts">
	import type { Snippet } from 'svelte';

	let { children, error }: { children: Snippet; error?: boolean } = $props();
</script>

<div class:error>{@render children()}</div>

<style>
	div {
		font-size: var(--small-font-size);
		font-style: italic;
	}

	.error {
		background: var(--error-color);
		color: var(--background-color);
		padding: var(--spacing);
		border-radius: var(--roundedness);
	}

	.error :global(a) {
		color: var(--background-color);
	}
</style>
