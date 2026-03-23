<script lang="ts">
	import type LocaleText from '$lib/locales/Locale';
	import Text from '$lib/locales/Text.svelte';

	let { good = true, label }: {
		good?: boolean;
		label: (l: LocaleText) => string;
	} = $props();
</script>

<span class="status" class:good><Text path={label} markdown /></span>

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
