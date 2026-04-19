<script lang="ts">
	import type LocaleText from '$lib/locales/Locale';
	import type { ButtonText, ConfirmButtonText } from '$lib/locales/Locale';
	import Text from '$lib/locales/Text.svelte';
	import { getLocaleContext } from '$routes/Contexts';
	import type { Snippet } from 'svelte';

	let {
		action,
		strings,
		children = undefined,
		active = true,
		formaction = undefined,
		name = undefined,
		type = 'button',
		view: _ = $bindable(undefined),
		end = false,
		background = true,
		small = false,
		testid = undefined
	}: {
		children?: Snippet;
		action: ((event?: Event) => void) | ((event?: Event) => Promise<void>);
		strings: (locale: LocaleText) => ButtonText | ConfirmButtonText;
		active?: boolean;
		formaction?: string | undefined;
		name?: string | undefined;
		type?: 'submit' | 'button';
		view?: HTMLButtonElement | undefined;
		end?: boolean | undefined;
		background?: boolean;
		small?: boolean;
		testid?: string;
	} = $props();

	/** True if we're evaluating the action. Allows us to deactivate button while waiting for a promise. */
	let acting = $state(false);

	/** True if this is a confirm button and we're getting confirmation. */
	let confirming = $state(false);

	let locale = getLocaleContext();

	let buttonText = $derived(strings(locale()));
	let warn = $derived(buttonText.warn);
	let tip = $derived(buttonText.tip);

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
		onclick={async (event) => await act(event)}
		>{#if children}{@render children()}{:else}<Text path={(l) => strings(l).label} />{/if}</button
	>
{:else}
	<div class="row">
		<button onclick={() => (confirming = false)}><Text path={(l) => l.shorthand.delete} /></button>
		<button
			data-testid={testid}
			class:warn={warn !== undefined}
			onclick={async (event) => await act(event)}
			><Text path={(l) => strings(l).warn ?? ''} /></button
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
		box-shadow: 2px 3px 0 rgba(0, 0, 0, 0.2);
		transition:
			box-shadow 150ms ease-out,
			transform 150ms ease-out;
	}

	button.small {
		font-size: var(--extra-small-font-size);
	}

	button.background {
		background: var(--salient-color);
		color: var(--background-color);
	}

	.row button:last-child {
		flex-grow: 1;
	}

	button:not([disabled]):hover {
		box-shadow: 3px 4px 0 rgba(0, 0, 0, 0.25);
		transform: translate(-1px, -1.5px);
	}

	button:not([disabled]):active,
	button:not([disabled]):focus {
		box-shadow: none;
		transform: translate(2px, 3px);
		transition-duration: 60ms;
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
		box-shadow: none;
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
