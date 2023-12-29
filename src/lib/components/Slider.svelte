<script lang="ts">
	export let min: number;
	export let max: number;
	export let value: number;
	export let step: number;
	export let change: undefined | ((value: number) => void) = undefined;

	let view: HTMLInputElement;

	function handleInput() {
		if (view) value = parseFloat(view.value);
		if (change) change(value);
	}
</script>

<input bind:this={view} type="range" {min} {max} {value} {step} on:input={handleInput} />

<style>
	input {
		display: inline-block;
		font-size: inherit;
		color: inherit;
		accent-color: var(--salient-color);
	}

	input:focus {
		outline-color: var(--focus-color);
	}
</style>
