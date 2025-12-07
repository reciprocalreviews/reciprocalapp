<script lang="ts">
	import { tick } from 'svelte';
	import Feedback from './Feedback.svelte';
	import Tip from './Tip.svelte';

	type Props = {
		text: string;
		label?: string | undefined;
		placeholder?: string;
		size?: number | undefined;
		active?: boolean;
		name?: string | undefined;
		/** Given a string, return a message describing invalidity, or nothing */
		valid?: undefined | ((text: string) => string | undefined);
		inline?: boolean;
		password?: boolean;
		view?: HTMLInputElement | HTMLTextAreaElement | undefined;
		done?: ((() => void) | undefined) | undefined;
		note?: string | undefined;
	};

	let {
		text = $bindable(''),
		placeholder = '',
		note,
		label,
		size = undefined,
		active = true,
		name = undefined,
		valid = undefined,
		inline = true,
		password = false,
		view = $bindable(undefined),
		done = undefined
	}: Props = $props();

	let error = $derived(valid ? valid(text) : undefined);
	let isValid = $derived(error === undefined);
	let measure = $state<HTMLSpanElement | undefined>(undefined);
	let width = $state(0);
	let height = $state(0);

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
			<span class="label">{label}</span>
		{/if}
		{#if inline}
			<input
				bind:value={text}
				bind:this={view}
				class:active
				{name}
				disabled={!active}
				{size}
				onfocus={() => (wasFocused = true)}
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
				onfocus={() => (wasFocused = true)}
				bind:value={text}
				bind:this={view}
				cols={size}
				style:width={size ? undefined : 'auth'}
				style:height={size ? undefined : height + 'px'}
				onkeydown={(event) =>
					event.key === 'Enter' && event.metaKey && done ? edit(event) : undefined}
			></textarea>
		{/if}
		<span class="ruler" class:inline class:active={!active} bind:this={measure}
			>{text.length === 0 ? placeholder : text + (inline ? '' : '\xa0\n')}</span
		>
	</label>
	{#if error !== undefined && wasFocused}
		<Feedback error={error !== undefined && wasFocused}
			>{#if error && wasFocused}{error}{/if}</Feedback
		>
	{/if}
	{#if note}
		<Tip border={false}>{note}</Tip>
	{/if}
</div>

<style>
	.field {
		display: flex;
		flex-direction: column;
		gap: calc(var(--spacing) / 2);
		flex-grow: 1;
	}

	input {
		border: none;
		border-bottom: var(--thick-border-width) solid var(--text-color);
		padding: calc(var(--spacing) / 2);
		border-top-right-radius: var(--roundedness);
		border-top-left-radius: var(--roundedness);
		box-shadow: inset 3px 3px 3px rgba(0, 0, 0, 0.1);
		font-family: inherit;
		line-height: inherit;
		font-size: inherit;
		font-weight: inherit;
		font-style: inherit;
		background: var(--background-color);
		overflow: visible !important;
		min-width: 2em;
		display: none;
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
		border: none;
		padding: calc(var(--spacing) / 2);
		border-top-right-radius: var(--roundedness);
		border-bottom-right-radius: var(--roundedness);
		box-shadow: inset 3px 3px 3px rgba(0, 0, 0, 0.1);
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
		overflow: hidden;
		display: none;
	}

	.ruler {
		position: absolute;
		top: calc(var(--spacing) / 2);
		left: calc(var(--spacing) / 2);
		width: fit-content;
		display: inline-block;
		white-space: pre;
		visibility: hidden;
	}

	.ruler.inline {
		display: inline;
	}

	.ruler.active {
		position: static;
		visibility: visible;
		white-space: wrap;
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
		border-color: var(--error-color);
	}

	input:focus,
	textarea:focus {
		outline: none;
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
