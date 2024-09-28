<script lang="ts">
	type Props = {
		text: string;
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
		size = undefined,
		padded = true,
		active = true,
		name = undefined,
		valid = undefined,
		inline = true,
		password = false,
		view = $bindable(undefined)
	}: Props = $props();

	let isValid = $derived(valid ? valid(text) : true);
	let height = $derived(text ? (view?.scrollHeight ?? 0) : 0);
</script>

{#if inline}
	<input
		bind:value={text}
		bind:this={view}
		{name}
		disabled={!active}
		class:padded
		{size}
		style:width={size === undefined
			? (text.length === 0 ? placeholder.length : text.length) + 0.5 + 'ch'
			: undefined}
		class:invalid={!isValid}
		{placeholder}
		type={password ? 'password' : 'text'}
	/>
{:else}
	<textarea
		class:padded
		class:invalid={!isValid}
		disabled={!active}
		{placeholder}
		bind:value={text}
		bind:this={view}
		cols={size}
		style:width={size ? undefined : '100%'}
		style:height={size ? undefined : height + 'px'}
		rows={text.split('\n').length}
	></textarea>
{/if}

<style>
	input {
		border: none;
		border-bottom: var(--thick-border) solid var(--text-color);
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
		border-left: var(--thick-border) solid var(--text-color);
		margin-left: calc(-1 * (var(--spacing)));
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

	input.padded,
	textarea.padded {
		padding: calc(var(--spacing) / 2);
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
</style>
