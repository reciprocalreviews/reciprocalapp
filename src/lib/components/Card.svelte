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
		expand = $bindable(false),
		controls
	}: {
		children: Snippet;
		controls?: Snippet;
		icon: string | number;
		header: string;
		note: string;
		subheader?: boolean;
		group?: 'admins' | 'minters' | 'stewards' | 'invite only';
		full?: boolean;
		expand?: boolean;
	} = $props();
</script>

{#snippet top()}
	{header}
	{#if group}<div class="group"><Tag>{group}</Tag></div>{/if}
{/snippet}

<div class="card" class:full class:expand>
	<div
		class="header"
		role="button"
		onclick={() => (expand = !expand)}
		onkeydown={(e) => (e.key === 'Enter' || e.key === ' ') && (expand = !expand)}
		tabindex="0"
		title={expand ? 'Collapse this card' : 'Expand this card'}
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
		{#if controls}
			<div>
				{@render controls()}
			</div>
		{/if}
	</div>
	{#if expand}
		<div class="body">
			{@render children()}
		</div>
	{/if}
</div>

<style>
	.card {
		display: flex;
		flex-direction: column;
		gap: calc(2 * var(--spacing));
		border-radius: var(--roundedness);
		border: var(--border-color) solid var(--border-width);
		flex: 1;
		min-width: 12em;
	}

	.body {
		padding: var(--spacing);
		padding-block-start: 0;
		display: flex;
		flex-direction: column;
		gap: var(--spacing);
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
		padding: var(--spacing);
		padding-block-end: 0;
		flex-wrap: nowrap;
		align-items: middle;
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

	:not(.expand) h2,
	:not(.expand) h3 {
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
