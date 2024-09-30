<script lang="ts">
	import { tick } from 'svelte';

	type Props = {
		text: string;
		label: string;
		placeholder: string;
		size?: number | undefined;
		padded?: boolean;
		active?: boolean;
		name?: string | undefined;
		valid?: undefined | ((text: string) => boolean);
		inline?: boolean;
		password?: boolean;
		view?: HTMLInputElement | HTMLTextAreaElement | undefined;
	};

	let {
		text = $bindable(''),
		placeholder,
		label,
		size = undefined,
		active = true,
		name = undefined,
		valid = undefined,
		inline = true,
		password = false,
		view = $bindable(undefined)
	}: Props = $props();

	let isValid = $derived(valid ? valid(text) : true);
	let measure = $state<HTMLSpanElement | undefined>(undefined);
	let width = $state(0);
	let height = $state(0);

	$effect(() => {
		width = measure?.clientWidth ?? 0;
		height = measure?.clientHeight ?? 0;
		if (text)
			tick().then(() => {
				width = measure?.clientWidth ?? 0;
				height = measure?.clientHeight ?? 0;
			});
	});
</script>

<label>
	<span class="label">{label}</span>
	{#if inline}
		<input
			bind:value={text}
			bind:this={view}
			{name}
			disabled={!active}
			{size}
			style:width={size === undefined ? (width === 0 ? 'auto' : width + 'px') : undefined}
			class:invalid={!isValid}
			{placeholder}
			type={password ? 'password' : 'text'}
		/>
	{:else}
		<textarea
			class:invalid={!isValid}
			disabled={!active}
			{placeholder}
			bind:value={text}
			bind:this={view}
			cols={size}
			style:width={size ? undefined : 'auth'}
			style:height={size ? undefined : height + 'px'}
			rows={text.split('\n').length}
		></textarea>
	{/if}
	<span class="ruler" bind:this={measure}
		>{text.length === 0 ? placeholder : text + (inline ? '' : '\xa0')}</span
	>
</label>

<style>
	input {
		border: none;
		border-bottom: var(--thick-border-width) solid var(--text-color);
		padding: 0;
		padding-block: 0;
		padding-inline: 0;
		font-family: inherit;
		line-height: inherit;
		font-size: inherit;
		font-weight: inherit;
		font-style: inherit;
		background: var(--background-color);
		overflow: visible !important;
	}

	textarea {
		border: none;
		padding: 0;
		padding-left: var(--spacing);
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
	}

	.ruler {
		display: inline-block;
		width: fit-content;
		position: absolute;
		white-space: pre;
		top: 0;
		left: 0;
		visibility: hidden;
	}

	input[disabled],
	textarea[disabled] {
		border-color: var(--inactive-color);
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

	label {
		width: 100%;
		position: relative;
	}
</style>
