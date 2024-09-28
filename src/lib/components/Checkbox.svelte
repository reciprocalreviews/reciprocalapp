<script lang="ts">
	import type { ErrorID } from '$lib/data/Database';
	import { addError } from '../../routes/errors.svelte';

	export let on: boolean;
	export let change: undefined | ((on: boolean) => Promise<ErrorID | undefined>);
</script>

<label
	><input
		type="checkbox"
		aria-checked={on}
		checked={on}
		on:click={async () => {
			on = !on;
			if (change) {
				const error = await change(on);
				if (error) addError(error);
			}
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
