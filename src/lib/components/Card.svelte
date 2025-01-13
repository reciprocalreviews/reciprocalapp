<script lang="ts">
	import type { Snippet } from 'svelte';
	import Tag from './Tag.svelte';
	import Circle from './Circle.svelte';
	import Note from './Note.svelte';

	let {
		children,
		subheader = false,
		group,
		icon,
		header,
		note,
		full = false,
		expand = false
	}: {
		children: Snippet;
		icon: string | number;
		header: string;
		note: string;
		subheader?: boolean;
		group?: 'editors' | 'minters' | 'stewards' | 'invite only';
		full?: boolean;
		expand?: boolean;
	} = $props();

	let expanded = $state(expand);
</script>

{#snippet top()}
	{header}
	{#if group}<div class="group"><Tag>{group}</Tag></div>{/if}
{/snippet}

<div class="card" class:full class:expanded>
	<div
		class="header"
		role="button"
		onclick={() => (expanded = !expanded)}
		onkeydown={(e) => (e.key === 'Enter' || e.key === ' ') && (expanded = !expanded)}
		tabindex="0"
		title={expanded ? 'Collapse this card' : 'Expand this card'}
	>
		<Circle {icon}></Circle>
		<div class="text">
			{#if subheader}
				<h3>{@render top()}</h3>
			{:else}
				<h2>{@render top()}</h2>
			{/if}
			<Note>{note}</Note>
		</div>
	</div>
	{#if expanded}
		{@render children()}
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
		align-items: start;
		flex: 1;
	}

	.header {
		display: flex;
		flex-direction: row;
		gap: var(--spacing);
		flex-wrap: nowrap;
		cursor: pointer;
		border-bottom: solid transparent var(--thick-border-width);
	}

	.header:hover {
		background: var(--alternating-color);
	}

	.header:focus {
		outline: none;
		border-bottom: solid var(--thick-border-width) var(--focus-color);
		border-radius: var(--roundedness);
	}

	:not(.expanded) h2,
	:not(.expanded) h3 {
		border-bottom: none;
		margin-bottom: 0;
	}

	.text {
		display: flex;
		flex-direction: column;
		flex: 1;
	}

	.group {
		display: flex;
		flex-direction: row;
		gap: var(--spacing);
		align-items: start;
		margin-inline-start: auto;
	}
</style>
