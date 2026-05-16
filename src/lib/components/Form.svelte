<script lang="ts">
	import type { Snippet } from 'svelte';

	let { children }: { children: Snippet } = $props();
</script>

<form onsubmit={(e) => e.preventDefault()}>
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
		overflow: hidden;
	}
</style>