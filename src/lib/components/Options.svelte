<script lang="ts">
	import type LocaleText from '$lib/locales/Locale';
	import type { OptionsText } from '$lib/locales/Locale';
	import { getLocaleContext } from '$routes/Contexts';

	type Props = {
		options: { label: string; value: string | undefined }[];
		value: string | undefined;
		disabled?: boolean;
		onChange?: ((value: string | undefined) => void) | undefined;
		strings?: (l: LocaleText) => OptionsText;
	};

	let { options, value = $bindable(), onChange, disabled = false, strings }: Props = $props();

	const locale = getLocaleContext();
	const text = $derived(strings ? strings(locale()) : undefined);

	function handleChange(event: Event) {
		const target = event.target as HTMLSelectElement;
		if (onChange) onChange(target.value === '' ? undefined : target.value);
	}
</script>

<label>
	{#if text?.label}
		<span class="label">{text.label}</span>
	{/if}
	<select bind:value onchange={handleChange} {disabled}>
		{#each options as option}
			<option value={option.value}>{option.label}</option>
		{/each}
	</select>
</label>

<style>
	select {
		font-family: var(--font-face);
		font-size: var(--small-font-size);
		padding: var(--spacing-half);
		border: var(--border-color) solid var(--border-width);
		border-radius: var(--roundedness);
		width: fit-content;
		max-width: 100%;
		box-shadow: 2px 3px 0 rgba(0, 0, 0, 0.2);
		transition:
			box-shadow 150ms ease-out,
			transform 150ms ease-out;
	}

	select:not(:focus):hover {
		box-shadow: 3px 4px 0 rgba(0, 0, 0, 0.25);
		transform: translate(-1px, -1.5px);
	}

	select:active,
	select:focus {
		box-shadow: inset 1px 2px 4px rgba(0, 0, 0, 0.15);
		transform: translate(1px, 1px);
		transition-duration: 60ms;
		outline: none;
	}

	select:focus {
		border-color: var(--focus-color);
	}

	.label {
		font-size: var(--small-font-size);
		font-style: italic;
	}
</style>
