<script lang="ts">
	import type Locale from '$lib/locales/Locale';
	import type { LocaleText, NotedTextFieldText, TextFieldText } from '$lib/locales/Locale';
	import Text from '$lib/locales/Text.svelte';
	import { getLocaleContext } from '$routes/Contexts';
	import { tick } from 'svelte';
	import Feedback from './Feedback.svelte';
	import Tip from './Tip.svelte';

	type Props = {
		/** The current text in the field */
		text: string;
		/** The localization strings for the field */
		strings: (l: Locale) => TextFieldText | NotedTextFieldText;
		size?: number | undefined;
		active?: boolean;
		name?: string | undefined;
		/** Given a string, return a message describing invalidity, or nothing */
		valid?: undefined | ((text: string) => ((l: LocaleText) => string) | undefined);
		inline?: boolean;
		password?: boolean;
		view?: HTMLInputElement | HTMLTextAreaElement | undefined;
		done?: ((() => void) | undefined) | undefined;
		testid?: string;
	};

	let {
		text = $bindable(''),
		strings,
		size = undefined,
		active = true,
		name = undefined,
		valid = undefined,
		inline = true,
		password = false,
		view = $bindable(undefined),
		done = undefined,
		testid = undefined
	}: Props = $props();

	let error = $derived(valid ? valid(text) : undefined);
	let isValid = $derived(error === undefined);
	let measure = $state<HTMLSpanElement | undefined>(undefined);
	let width = $state(0);
	let height = $state(0);

	let locale = getLocaleContext();
	let labels = $derived(strings(locale()));
	let note = $derived('note' in labels ? labels.note : undefined);
	let label = $derived(labels.label);
	let placeholder = $derived(labels.placeholder);

	/** We keep track of the first focus to avoid showing validation errors until interaction. */
	let wasFocused = $state(false);

	let labelView = $state<HTMLLabelElement | undefined>(undefined);

	function resize() {
		if (view === undefined) return;
		width = measure?.clientWidth ?? 0;

		if (inline) height = measure?.clientHeight ?? 0;
		// Reset the textarea height before measuring scroll height.
		else {
			view.style.height = '0';
			height = inline ? (measure?.clientHeight ?? 0) : (view?.scrollHeight ?? 0);
			view.style.height = height + 'px';
		}
	}

	$effect(() => {
		text;
		tick().then(() => resize());
	});

	function edit(event: Event) {
		if (done) {
			done();
			if (labelView) labelView.scrollLeft = 0;
			event.stopPropagation();
		}
	}
</script>

<div class="field">
	<label bind:this={labelView}>
		{#if label}
			<span class="label"><Text path={label} /></span>
		{/if}
		{#if inline}
			<input
				bind:value={text}
				bind:this={view}
				class:active
				data-testid={testid}
				{name}
				disabled={!active}
				{size}
				onfocus={() => (wasFocused = true)}
				onblur={() => done?.()}
				style:width={size === undefined ? (width === 0 ? 'auto' : width + 'px') : undefined}
				class:invalid={!isValid}
				{placeholder}
				type={password ? 'password' : 'text'}
				onkeydown={(event) => (event.key === 'Enter' && done ? edit(event) : undefined)}
			/>
		{:else}
			<textarea
				class:invalid={!isValid}
				class:active
				disabled={!active}
				{placeholder}
				data-testid={testid}
				onfocus={() => (wasFocused = true)}
				onblur={() => done?.()}
				bind:value={text}
				bind:this={view}
				cols={size}
				style:width={size ? undefined : 'auth'}
				style:height={size ? undefined : height + 'px'}
				onkeydown={(event) =>
					event.key === 'Enter' && event.metaKey && done ? edit(event) : undefined}
			></textarea>
		{/if}
		<span
			class="ruler"
			class:inline
			class:active={!active}
			class:placeholder={text.length === 0}
			bind:this={measure}>{text.length === 0 ? placeholder : text + (inline ? '' : '\xa0\n')}</span
		>
	</label>
	{#if error !== undefined && wasFocused}
		<Feedback error={error !== undefined && wasFocused} text={error!} />
	{/if}
	{#if note}
		<Tip border={false}>{note}</Tip>
	{/if}
</div>

<style>
	.field {
		display: flex;
		flex-direction: column;
		gap: var(--spacing-half);
		flex-grow: 1;
	}

	input {
		border: var(--border-width) solid var(--border-color);
		border-bottom-width: var(--thick-border-width);
		padding: var(--spacing-half);
		border-top-right-radius: var(--roundedness);
		border-top-left-radius: var(--roundedness);
		font-family: inherit;
		line-height: inherit;
		font-size: inherit;
		font-weight: inherit;
		font-style: inherit;
		background: var(--background-color);
		overflow: visible !important;
		min-width: 2em;
		flex-grow: 1;
		max-width: fit-content;
		display: none;
		box-shadow: 2px 3px 0 rgba(0, 0, 0, 0.15);
		transition:
			box-shadow 150ms ease-out,
			transform 150ms ease-out;
	}

	input::placeholder {
		font-style: italic;
	}

	input.active {
		display: inline;
	}

	textarea.active {
		display: block;
	}

	textarea {
		border: var(--border-width) solid var(--border-color);
		padding: var(--spacing-half);
		border-top-right-radius: var(--roundedness);
		border-bottom-right-radius: var(--roundedness);
		border-left: var(--thick-border-width) solid var(--text-color);
		font-family: inherit;
		line-height: inherit;
		font-size: inherit;
		font-weight: inherit;
		font-style: inherit;
		background: var(--background-color);
		resize: none;
		min-width: 1em;
		min-height: 1em;
		flex-grow: 1;
		overflow: hidden;
		display: none;
		box-shadow: 2px 3px 0 rgba(0, 0, 0, 0.15);
		transition:
			box-shadow 150ms ease-out,
			transform 150ms ease-out;
	}

	input.active:not(:focus):hover,
	textarea.active:not(:focus):hover {
		box-shadow: 3px 4px 0 rgba(0, 0, 0, 0.2);
		transform: translate(-1px, -1.5px);
	}

	.ruler {
		position: absolute;
		top: var(--spacing-half);
		left: var(--spacing-half);
		width: fit-content;
		display: inline-block;
		white-space: pre;
		visibility: hidden;
		flex-grow: 1;
	}

	.ruler.active {
		position: static;
		visibility: visible;
		white-space: wrap;
		word-break: break-word;
	}

	.ruler.placeholder {
		font-style: italic;
	}

	input[disabled],
	textarea[disabled] {
		border-color: var(--inactive-color);
	}

	input[disabled] {
		border-bottom-style: dotted;
	}
	textarea[disabled] {
		border-left-style: dotted;
	}

	input.invalid,
	textarea.invalid {
		color: var(--error-color);
	}

	input.invalid {
		border-bottom-color: var(--error-color);
	}

	textarea.invalid {
		border-left-color: var(--error-color);
	}

	input:focus,
	textarea:focus {
		outline: none;
		box-shadow: inset 1px 2px 4px rgba(0, 0, 0, 0.15);
		transform: translate(1px, 1px);
		transition-duration: 60ms;
	}

	input:not(.invalid):focus {
		border-bottom-color: var(--focus-color);
	}

	textarea:not(.invalid):focus {
		border-color: var(--focus-color);
	}

	.label {
		font-style: italic;
		font-size: var(--small-font-size);
	}
</style>
