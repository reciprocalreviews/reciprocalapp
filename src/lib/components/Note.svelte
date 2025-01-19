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
		color: var(--error-color);
	}
</style>
