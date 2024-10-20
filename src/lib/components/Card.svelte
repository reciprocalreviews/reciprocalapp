<script lang="ts">
	import type { Snippet } from 'svelte';
	import Tag from './Tag.svelte';

	let {
		header = undefined,
		group,
		full = false,
		children
	}: {
		header?: string | undefined;
		group?: 'editors' | 'stewards';
		full?: boolean;
		children: Snippet;
	} = $props();
</script>

<div class="card" class:full>
	{#if header}
		<h2>
			{header}
			{#if group}<Tag>{group}</Tag>{/if}
		</h2>
	{/if}
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
	}

	.full {
		min-width: calc(100% - var(--spacing) * 3);
	}

	h2 {
		display: flex;
		align-items: center;
		gap: var(--spacing);
	}
</style>
