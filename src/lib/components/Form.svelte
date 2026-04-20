<script lang="ts">
	import type { Snippet } from 'svelte';

	let { inline = false, children }: { inline?: boolean; children: Snippet } = $props();
</script>

<form class:inline onsubmit={(e) => e.preventDefault()}>{@render children()}</form>

<style>
	form {
		display: flex;
		flex-direction: column;
		gap: var(--spacing-twice);
		align-items: flex-start;
		border: var(--border-color) solid var(--border-width);
		padding: var(--spacing);
		border-radius: var(--roundedness);
	}

	form.inline {
		flex-direction: row;
		flex-wrap: wrap;
		align-items: baseline;
		gap: var(--spacing);
		row-gap: var(--spacing);
	}
</style>
