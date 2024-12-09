<script lang="ts">
	import type { Snippet } from 'svelte';
	import Tag from './Tag.svelte';
	import Button from './Button.svelte';

	let {
		header,
		detail,
		subheader = false,
		group,
		full = false,
		expand = false
	}: {
		header: Snippet;
		detail: Snippet;
		subheader?: boolean;
		group?: 'editors' | 'minters' | 'stewards';
		full?: boolean;
		expand?: boolean;
	} = $props();

	let expanded = $state(expand);
</script>

{#snippet content()}
	{@render header()}
	{#if group}<Tag>{group} only</Tag>{/if}
	<Button
		tip={expanded ? 'Collapse this card' : 'Expand this card'}
		action={() => (expanded = !expanded)}
		end
		>{#if expanded}⏷{:else}⏵{/if}</Button
	>
{/snippet}

<div class="card" class:full={expanded && full} class:expanded>
	{#if !subheader}
		<h2>
			{@render content()}
		</h2>
	{:else}
		<h3>
			{@render content()}
		</h3>
	{/if}
	{#if expanded}
		{@render detail()}
	{/if}
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
		min-width: 12em;
	}

	.full {
		min-width: calc(100% - var(--spacing) * 3);
	}

	h2,
	h3 {
		display: flex;
		align-items: center;
		gap: var(--spacing);
		align-items: baseline;
	}

	:not(.expanded) h2,
	:not(.expanded) h3 {
		border-bottom: none;
		margin-bottom: 0;
	}
</style>
