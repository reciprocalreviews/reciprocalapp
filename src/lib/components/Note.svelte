<script lang="ts">
	import Text from '$lib/locales/Text.svelte';
	import type LocaleText from '$lib/locales/Locale';

	let { path }: { path: (l: LocaleText) => string } = $props();
</script>

<div class="markdown"><Text {path} markdown /></div>

<style>
	div {
		font-size: var(--small-font-size);
		font-style: italic;
	}
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
