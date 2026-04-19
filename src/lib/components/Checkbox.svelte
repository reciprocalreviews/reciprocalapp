<script lang="ts">
	import { handle } from '../../routes/feedback.svelte';
	import type { Result } from '$lib/data/CRUD';
	import type LocaleText from '$lib/locales/Locale';
	import Text from '$lib/locales/Text.svelte';

	let {
		on = $bindable(),
		change = undefined,
		active = true,
		label,
		testid = undefined
	}: {
		/** Whether the box is selected */
		on: boolean;
		/** Whether the checkbox is enabled */
		active?: boolean;
		change?: undefined | ((on: boolean) => Promise<Result>);
		label: (l: LocaleText) => string;
		testid?: string | undefined;
	} = $props();
</script>

<label
	><input
		type="checkbox"
		data-testid={testid}
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
	/><span class="text"><Text path={label} markdown /></span></label
>

<style>
	label {
		display: inline-flex;
		flex-direction: row;
		align-self: flex-start;
		gap: var(--spacing);
		align-items: baseline;
		font-size: var(--small-font-size);
		font-style: italic;
		padding: 2px 4px;
		border-radius: var(--roundedness);
		box-shadow: 2px 3px 0 rgba(0, 0, 0, 0.2);
		background: var(--background-color);
		transition:
			box-shadow 150ms ease-out,
			transform 150ms ease-out;
	}

	label:hover {
		cursor: pointer;
		box-shadow: 3px 4px 0 rgba(0, 0, 0, 0.25);
		transform: translate(-1px, -1.5px);
	}

	label:has(input:active),
	label:has(input:focus) {
		box-shadow: none;
		transform: translate(2px, 3px);
		transition-duration: 60ms;
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
