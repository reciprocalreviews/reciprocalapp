<script lang="ts">
	import type { Snippet } from 'svelte';
	import Tag from './Tag.svelte';

	let {
		header,
		group,
		children
	}: { header: string; group?: 'editors' | 'stewards'; children: Snippet } = $props();
</script>

<div class="card">
	<h2>
		{header}
		{#if group}<Tag>{group}</Tag>{/if}
	</h2>
	{@render children()}
</div>

<style>
	.card {
		display: flex;
		flex-direction: column;
		gap: calc(2 * var(--spacing));
		padding: var(--spacing);
		border-radius: var(--roundedness);
		border: var(--border-color) solid var(--border-width);
		flex: 1;
		min-width: 10em;
		max-width: 40em;
	}

	h2 {
		display: flex;
		align-items: center;
		gap: var(--spacing);
	}
</style>
