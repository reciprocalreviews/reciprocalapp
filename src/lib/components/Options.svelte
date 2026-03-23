<script lang="ts">
	import { getLocaleContext } from '$routes/Contexts';
	import type LocaleText from '$lib/locales/Locale';
	import type { OptionsText } from '$lib/locales/Locale';

	type Props = {
		options: { label: string; value: string | undefined }[];
		value: string | undefined;
		disabled?: boolean;
		onChange?: ((value: string | undefined) => void) | undefined;
		strings?: (l: LocaleText) => OptionsText;
	};

	let { options, value = $bindable(), onChange, disabled = false, strings }: Props = $props();

	const locale = getLocaleContext();
	const text = $derived(strings ? strings(locale) : undefined);

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
	}

	select:focus {
		outline: var(--focus-color) solid var(--thick-border-width);
	}

	.label {
		font-size: var(--small-font-size);
		font-style: italic;
	}
</style>
