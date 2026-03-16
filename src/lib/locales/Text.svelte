<script lang="ts">
	import { getLocaleContext } from '$routes/Contexts';
	import type LocaleText from './Locale';
	import { marked } from 'marked';

	let {
		path,
		markdown = false
	}: { path: (locale: LocaleText) => string | string[]; markdown?: boolean } = $props();

	const locale = getLocaleContext();

	// Construct the text from the locale file.
	const text = $derived.by(() => {
		const stuff = path(locale);
		// If it's an array, treat it like multiple paragraphs and join with newlines. Otherwise, just return the string.
		if (Array.isArray(stuff)) {
			return stuff.join('\n\n');
		} else {
			return stuff;
		}
	});
</script>

{#if markdown}
	{@html marked(text)}
{:else}
	{text}
{/if}
