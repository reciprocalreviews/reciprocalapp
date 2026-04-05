<script lang="ts">
	import type LocaleText from '$lib/locales/Locale';
	import type { SliderText } from '$lib/locales/Locale';
	import { getLocaleContext } from '$routes/Contexts';

	interface Props {
		min: number;
		max: number;
		value: number;
		step: number;
		strings: (l: LocaleText) => SliderText;
		active?: boolean;
		change?: undefined | ((value: number) => void);
		/** If true, fires change event during drag. */
		immediately?: boolean;
	}

	let {
		min,
		max,
		value = $bindable(),
		step,
		active = true,
		strings,
		change = undefined,
		immediately = true
	}: Props = $props();

	const locale = getLocaleContext();
	const text = $derived(strings(locale()));

	let view: HTMLInputElement | undefined = $state();

	function handleInput() {
		if (view) value = parseFloat(view.value);
		if (change) change(value);
	}
</script>

<label>
	<span class="label">{text.label}</span>
	<div class="slider">
		<input
			bind:this={view}
			disabled={!active}
			aria-disabled={!active}
			type="range"
			{min}
			{max}
			{value}
			{step}
			oninput={immediately ? handleInput : undefined}
			onchange={handleInput}
		/>
		<span class="value">{value}{text.suffix ?? ''}</span>
	</div>
</label>

<style>
	.slider {
		display: flex;
		flex-direction: row;
		gap: var(--spacing);
		align-items: center;
	}

	input {
		display: inline-block;
		font-size: inherit;
		color: inherit;
		accent-color: var(--salient-color);
		width: 100%;
	}

	input:focus {
		outline: var(--focus-color) solid var(--thick-border-width);
		border-radius: var(--roundedness);
	}

	label {
		width: 100%;
		position: relative;
		overflow: hidden;
		font-size: var(--small-font-size);
		font-style: italic;
	}
</style>
