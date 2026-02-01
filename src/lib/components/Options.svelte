<script lang="ts">
	type Props = {
		options: { label: string; value: string | undefined }[];
		value: string | undefined;
		disabled?: boolean;
		onChange?: ((value: string) => void) | undefined;
		label: string;
	};

	let { options, value = $bindable(), onChange, disabled = false, label }: Props = $props();

	function handleChange(event: Event) {
		const target = event.target as HTMLSelectElement;
		if (onChange) onChange(target.value);
	}
</script>

<label>
	<span class="label">{label}</span>
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
		padding: calc(var(--spacing) / 2);
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
