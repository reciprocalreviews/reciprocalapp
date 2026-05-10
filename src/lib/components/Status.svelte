<script lang="ts">
	import type LocaleText from '$lib/locales/Locale';
	import Text from '$lib/locales/Text.svelte';

	let {
		good = true,
		label,
		testid
	}: {
		good?: boolean;
		label: (l: LocaleText) => string;
		testid?: string;
	} = $props();
</script>

<span class="status" class:good data-testid={testid}><Text path={label} /></span>

<style>
	.status {
		background: var(--error-color);
		color: var(--background-color);
		padding: calc(var(--spacing) / 4) var(--spacing-half) calc(var(--spacing) / 4)
			var(--spacing-half);
		font-size: var(--small-font-size);
		border-radius: var(--roundedness);
		white-space: nowrap;
	}

	.good {
		background: var(--salient-color);
	}
</style>
