<script lang="ts">
	import type { Snippet } from 'svelte';
	import { ConfirmLabel, DeleteLabel } from './Labels';

	let {
		action,
		tip,
		children,
		active = true,
		formaction = undefined,
		name = undefined,
		type = undefined,
		view = $bindable(undefined),
		warn = false
	}: {
		children: Snippet;
		action: (event: Event) => void;
		tip: string;
		active?: boolean;
		formaction?: string | undefined;
		name?: string | undefined;
		type?: 'submit' | undefined;
		view?: HTMLButtonElement | undefined;
		warn?: boolean;
	} = $props();

	let confirming = $state(false);
</script>

{#if !warn || !confirming}
	<button
		bind:this={view}
		{name}
		{formaction}
		{type}
		title={tip}
		aria-label={tip}
		disabled={!active}
		class:warn
		onclick={(event) => {
			if (active)
				if (warn) confirming = true;
				else action(event);
		}}>{@render children()}</button
	>
{:else}
	<div class="row">
		<button onclick={() => (confirming = false)}>{DeleteLabel}</button>
		<button class:warn onclick={(event) => action(event)}>{@render children()}</button>
	</div>
{/if}

<style>
	button {
		font-family: var(--font-face);
		font-size: var(--small-font-size);
		border: var(--border-color);
		border-radius: var(--roundedness);
		padding: var(--spacing);
		background: var(--text-color);
		color: var(--background-color);
		cursor: pointer;
		white-space: nowrap;
	}

	.row button:last-child {
		flex-grow: 1;
	}

	button[disabled] {
		background: var(--inactive-color);
		cursor: auto;
	}

	button:focus {
		outline: var(--focus-color) solid var(--thick-border-width);
	}

	button:not(.inactive):hover {
		transform: scale(1.05);
	}

	button.warn {
		background-color: var(--error-color);
		color: var(--background-color);
	}

	.row {
		display: flex;
		flex-direction: row;
		align-items: center;
		gap: var(--spacing);
	}
</style>
