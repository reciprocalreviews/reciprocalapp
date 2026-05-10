<script lang="ts">
	import type { Snippet } from 'svelte';

	let {
		inline = false,
		modern = false,
		children
	}: { inline?: boolean; modern?: boolean; children: Snippet } = $props();
</script>

<form class:inline class:modern onsubmit={(e) => e.preventDefault()}>
	{@render children()}
</form>

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

	form.modern {
		gap: 0;
		align-items: stretch;
		border: var(--border-width) solid var(--border-color);
		border-radius: var(--roundedness);
		padding: 0;
		overflow: hidden;
	}
</style>