<script lang="ts">
	import type { Snippet } from 'svelte';

	let { children }: { children: Snippet } = $props();
</script>

<p>{@render children()}</p>

<style>
	p {
		font-size: var(--small-font-size);
		font-style: italic;
	}
</style>
