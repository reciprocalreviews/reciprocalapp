<script lang="ts">
	import type { Snippet } from 'svelte';
	import { DeleteLabel } from './Labels';

	let {
		action,
		tip,
		children,
		active = true,
		formaction = undefined,
		name = undefined,
		type = undefined,
		view = $bindable(undefined),
		warn = undefined,
		end = false
	}: {
		children: Snippet;
		action: ((event?: Event) => void) | ((event?: Event) => Promise<void>);
		tip: string;
		active?: boolean;
		formaction?: string | undefined;
		name?: string | undefined;
		type?: 'submit' | undefined;
		view?: HTMLButtonElement | undefined;
		warn?: string | undefined;
		end?: boolean | undefined;
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
		class:warn={warn !== undefined}
		class:end
		onclick={(event) => {
			if (active)
				if (warn) confirming = true;
				else action(event);
		}}>{@render children()}</button
	>
{:else}
	<div class="row">
		<button onclick={() => (confirming = false)}>{DeleteLabel}</button>
		<button
			class:warn={warn !== undefined}
			onclick={async (event) => {
				await action(event);
				confirming = false;
			}}
			>{#if confirming}{warn}{:else}{@render children()}{/if}</button
		>
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

	button:not([disabled]):hover {
		transform: scale(1.05);
	}

	button:focus {
		outline: var(--focus-color) solid var(--thick-border-width);
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

	.end {
		margin-inline-start: auto;
	}
</style>
