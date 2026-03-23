<script lang="ts">
	import type { Snippet } from 'svelte';

	/** A lead paragraph, which is styled larger and italicized. */
	let { children }: { children: Snippet } = $props();
</script>

<p class="lead">{@render children()}</p>

<style>
	.lead {
		font-size: calc(var(--paragraph-font-size) + 6pt);
		font-style: italic;
		margin-bottom: 0;
	}
</style>
