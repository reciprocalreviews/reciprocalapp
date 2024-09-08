<script lang="ts">
	export let on: boolean;
	export let change: undefined | ((on: boolean) => void);
</script>

<label
	><input
		type="checkbox"
		aria-checked={on}
		checked={on}
		on:click={() => {
			on = !on;
			if (change) change(on);
		}}
	/><slot /></label
>

<style>
	label {
		display: flex;
		flex-direction: row;
		gap: var(--spacing);
		align-items: baseline;
	}

	input {
		accent-color: var(--salient-color);
		width: 20px;
		height: 20px;
	}

	input:focus {
		outline: solid 3px var(--focus-color);
	}
</style>
