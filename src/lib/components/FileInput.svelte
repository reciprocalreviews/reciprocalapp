<script lang="ts">
	import type Locale from '$lib/locales/Locale';
	import Text from '$lib/locales/Text.svelte';

	let {
		label,
		accept,
		onChange,
		testid
	}: {
		label: (l: Locale) => string;
		accept?: string;
		onChange: (event: Event) => void;
		testid?: string;
	} = $props();
</script>

<label class="file-input">
	<Text path={label} />
	<input type="file" {accept} onchange={onChange} data-testid={testid} />
</label>

<style>
	.file-input {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: var(--spacing-half);
		font-size: var(--small-font-size);
	}

	.file-input input[type='file'] {
		font-family: var(--font-face);
		font-size: var(--small-font-size);
	}

	.file-input input[type='file']::file-selector-button {
		font-family: var(--font-face);
		font-size: var(--small-font-size);
		padding: var(--spacing-half);
		border: none;
		border-radius: var(--roundedness);
		background: var(--salient-color);
		color: var(--background-color);
		cursor: pointer;
		margin-right: var(--spacing-half);
		box-shadow: 2px 3px 0 rgba(0, 0, 0, 0.2);
		transition:
			box-shadow 150ms ease-out,
			transform 150ms ease-out;
	}

	.file-input input[type='file']::file-selector-button:hover {
		box-shadow: 3px 4px 0 rgba(0, 0, 0, 0.25);
		transform: translate(-1px, -1.5px);
	}

	.file-input input[type='file']::file-selector-button:active {
		box-shadow: none;
		transform: translate(2px, 3px);
		transition-duration: 60ms;
	}
</style>
