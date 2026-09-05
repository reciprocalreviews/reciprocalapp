<script lang="ts">
	import type LocaleText from '$lib/locales/Locale';
	import Text from '$lib/locales/Text.svelte';

	let {
		good = true,
		neutral = false,
		label,
		testid
	}: {
		good?: boolean;
		/** For a state that is neither good nor a problem — a fact about the thing
		 * rather than a verdict on it. Takes precedence over `good`, since both
		 * of that prop's colours would misstate one. */
		neutral?: boolean;
		label: (l: LocaleText) => string;
		testid?: string;
	} = $props();
</script>

<span class="status" class:good={good && !neutral} class:neutral data-testid={testid}
	><Text path={label} /></span
>

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

	.neutral {
		background: var(--inactive-color);
	}
</style>
