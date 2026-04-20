<script lang="ts">
	import type LocaleText from '$lib/locales/Locale';
	import Text from '$lib/locales/Text.svelte';

	let {
		group = $bindable(),
		value,
		label,
		active = true,
		testid = undefined
	}: {
		group: string;
		value: string;
		label: (l: LocaleText) => string;
		active?: boolean;
		testid?: string;
	} = $props();
</script>

<label>
	<input
		type="radio"
		bind:group
		{value}
		disabled={!active}
		data-testid={testid}
	/><span class="text"><Text path={label} /></span>
</label>

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
		border: none;
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
		outline: none;
	}

	input:focus {
		accent-color: var(--focus-color);
	}
</style>
