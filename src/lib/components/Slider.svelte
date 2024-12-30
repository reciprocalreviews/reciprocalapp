<script lang="ts">
	import type { Snippet } from 'svelte';

	interface Props {
		min: number;
		max: number;
		value: number;
		step: number;
		label?: string | undefined;
		change?: undefined | ((value: number) => void);
		children?: Snippet;
	}

	let {
		min,
		max,
		value = $bindable(),
		step,
		label = undefined,
		change = undefined,
		children
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
		<span class="value">{@render children?.()}</span>
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
	}
</style>
