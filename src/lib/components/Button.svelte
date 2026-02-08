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
		view: _ = $bindable(undefined),
		warn = undefined,
		end = false,
		background = true,
		small = false,
		testid = undefined
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
		background?: boolean;
		small?: boolean;
		testid?: string;
	} = $props();

	/** True if we're evaluating the action. Allows us to deactivate button while waiting for a promise. */
	let acting = $state(false);

	/** True if this is a confirm button and we're getting confirmation. */
	let confirming = $state(false);

	async function act(event: Event) {
		if (active) {
			if (warn && !confirming) {
				confirming = true;
			} else {
				acting = true;
				event.stopPropagation();
				await action(event);
				acting = false;
				confirming = false;
			}
		}
	}
</script>

{#if !warn || !confirming}
	<button
		bind:this={_}
		{name}
		{formaction}
		{type}
		title={tip}
		aria-label={tip}
		data-testid={testid}
		disabled={!active || acting}
		class:background
		class:warn={warn !== undefined}
		class:end
		class:small
		onclick={async (event) => await act(event)}>{@render children()}</button
	>
{:else}
	<div class="row">
		<button onclick={() => (confirming = false)}>{DeleteLabel}</button>
		<button
			data-testid={testid}
			class:warn={warn !== undefined}
			onclick={async (event) => await act(event)}>{warn}</button
		>
	</div>
{/if}

<style>
	button {
		font-family: var(--font-face);
		font-size: var(--small-font-size);
		border: var(--border-color);
		border-radius: var(--roundedness);
		padding: var(--spacing-half);
		background: none;
		color: var(--foreground-color);
		cursor: pointer;
		white-space: nowrap;
	}

	button.small {
		font-size: var(--extra-small-font-size);
	}

	button.background {
		background: var(--text-color);
		color: var(--background-color);
	}

	.row button:last-child {
		flex-grow: 1;
	}

	button:not([disabled]):hover {
		transform: scaleY(1.05);
	}

	button:focus {
		outline: var(--focus-color) solid var(--thick-border-width);
	}

	button.warn {
		background-color: var(--error-color);
		color: var(--background-color);
	}

	button[disabled] {
		background: var(--inactive-color);
		cursor: auto;
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
