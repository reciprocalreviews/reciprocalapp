<script lang="ts">
	export let min: number;
	export let max: number;
	export let value: number;
	export let step: number;
	export let label: string | undefined = undefined;
	export let unit: string | undefined = undefined;
	export let change: undefined | ((value: number) => void) = undefined;

	let view: HTMLInputElement;

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
		<input bind:this={view} type="range" {min} {max} {value} {step} on:input={handleInput} />
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
