<script lang="ts">
	import type Locale from '$lib/locales/Locale';
	import Text from '$lib/locales/Text.svelte';

	interface Props {
		text: (l: Locale) => string;
		inputs?: Record<string, string>;
	}

	const { text, inputs = {} }: Props = $props();
</script>

<div class="markdown"><Text markdown path={text} {inputs} /></div>

<style>
	.markdown :global(p),
	.markdown :global(ul),
	.markdown :global(ol) {
		margin-bottom: 0.75em;
	}
	.markdown :global(p:last-child),
	.markdown :global(ul:last-child),
	.markdown :global(ol:last-child) {
		margin-bottom: 0;
	}
	.markdown :global(ul),
	.markdown :global(ol) {
		padding-left: 1.5em;
	}
</style>
