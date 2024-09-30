<script lang="ts">
	import type { ErrorID } from '$lib/data/Database';
	import type { Snippet } from 'svelte';
	import { addError } from '../../routes/errors.svelte';

	let {
		on,
		change,
		children
	}: {
		on: boolean;
		change: undefined | ((on: boolean) => Promise<ErrorID | undefined>);
		children: Snippet;
	} = $props();
</script>

<label
	><input
		type="checkbox"
		aria-checked={on}
		checked={on}
		onclick={async () => {
			on = !on;
			if (change) {
				const error = await change(on);
				if (error) addError(error);
			}
		}}
	/>{@render children()}</label
>

<style>
	input {
		accent-color: var(--salient-color);
		width: 20px;
		height: 20px;
	}

	input:focus {
		outline: solid 3px var(--focus-color);
	}

	label {
		flex-direction: row;
	}
</style>
