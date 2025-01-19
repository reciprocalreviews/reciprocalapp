<script lang="ts">
	import type { ErrorID } from '$lib/data/CRUD';
	import type { Snippet } from 'svelte';
	import { handle } from '../../routes/feedback.svelte';

	let {
		on = $bindable(),
		change = undefined,
		children
	}: {
		on: boolean;
		change?: undefined | ((on: boolean) => Promise<ErrorID | undefined>);
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
				await handle(change(on));
			}
		}}
	/>{@render children()}</label
>

<style>
	input {
		accent-color: var(--salient-color);
		width: 20px;
		height: 20px;
		border-radius: var(--roundedness);
	}

	input:focus {
		outline: solid var(--thick-border-width) var(--focus-color);
	}

	label {
		flex-direction: row;
		gap: var(--spacing);
		align-items: center;
	}
</style>
