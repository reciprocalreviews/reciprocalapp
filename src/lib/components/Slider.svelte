<script lang="ts">
	interface Props {
		min: number;
		max: number;
		value: number;
		step: number;
		label?: string | undefined;
		unit?: string | undefined;
		change?: undefined | ((value: number) => void);
	}

	let {
		min,
		max,
		value = $bindable(),
		step,
		label = undefined,
		unit = undefined,
		change = undefined
	}: Props = $props();

	let view: HTMLInputElement | undefined = $state();

	function handleInput() {
		if (view) value = parseFloat(view.value);
		if (change) change(value);
	}
</script>

<label>
	{#if label}
		<span class="label">{label}</span>
	{/if}
	<div class="slider">
		<input bind:this={view} type="range" {min} {max} {value} {step} oninput={handleInput} />
		<span class="value"
			>{value}{#if unit}
				&nbsp;{unit}{/if}</span
		>
	</div>
</label>

<style>
	.slider {
		display: flex;
		flex-direction: row;
		gap: var(--spacing);
		align-items: baseline;
	}

	input {
		display: inline-block;
		font-size: inherit;
		color: inherit;
		accent-color: var(--salient-color);
	}

	input:focus {
		outline-color: var(--focus-color);
	}

	label {
		width: 100%;
		position: relative;
		overflow: hidden;
	}
</style>
