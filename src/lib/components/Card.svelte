<script lang="ts">
	import type { Snippet } from 'svelte';

	let { header, children }: { header: string; children: Snippet } = $props();
</script>

<div class="card">
	<h2>{header}</h2>
	{@render children()}
</div>

<style>
	.card {
		display: flex;
		flex-direction: column;
		gap: var(--spacing);
		padding: var(--spacing);
		border-radius: var(--roundedness);
		border: var(--border-color) solid var(--border-width);
		flex: 1;
		min-width: 10em;
		max-width: 40em;
	}
</style>
