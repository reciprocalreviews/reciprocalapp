<script lang="ts">
	import type { Snippet } from 'svelte';
	import { handle } from '../../routes/feedback.svelte';
	import type { Result } from '$lib/data/CRUD';

	let {
		on = $bindable(),
		change = undefined,
		active = true,
		children
	}: {
		/** Whether the box is selected */
		on: boolean;
		/** Whether the checkbox is enabled */
		active?: boolean;
		change?: undefined | ((on: boolean) => Promise<Result>);
		children?: Snippet;
	} = $props();
</script>

<label
	><input
		type="checkbox"
		aria-checked={on}
		aria-disabled={!active}
		disabled={!active}
		checked={on}
		onclick={async () => {
			on = !on;
			if (change) {
				await handle(change(on));
			}
		}}
	/><span class="text">{@render children?.()}</span></label
>

<style>
	label {
		display: flex;
		flex-direction: row;
		gap: var(--spacing);
		align-items: baseline;
		font-size: var(--small-font-size);
	}

	input {
		display: inline;
		accent-color: var(--salient-color);
		transform: scale(1.5);
		border-radius: var(--roundedness);
	}

	input:focus {
		outline: solid var(--thick-border-width) var(--focus-color);
	}
</style>
