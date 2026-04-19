<script lang="ts">
	import { getLocaleContext } from '$routes/Contexts';
	import { marked } from 'marked';
	import type LocaleText from './Locale';

	let {
		path,
		markdown = false,
		inputs = {}
	}: {
		path: string | ((locale: LocaleText) => string | string[]);
		markdown?: boolean;
		inputs?: Record<string, string>;
	} = $props();

	const locale = getLocaleContext();

	// Construct the text from the locale file.
	const text = $derived.by(() => {
		const loc = locale();

		const stuff = typeof path === 'string' ? path : path(loc);
		// If it's an array, treat it like multiple paragraphs and join with newlines. Otherwise, just return the string.
		let text = Array.isArray(stuff) ? stuff.join('\n\n') : stuff;

		// Replace any shorthand in the text with the corresponding shorthand in the locale file.
		text = text.replace(/\$(\w+)/g, (_, key) => {
			return key in loc.shorthand ? loc.shorthand[key as keyof typeof loc.shorthand] : `$${key}`;
		});

		// Replace any template inputs in the text with the corresponding values.
		text = text.replace(/\{(\w+)\}/g, (match, key) => (key in inputs ? inputs[key] : match));

		return text;
	});
</script>

{#if markdown}
	{@html marked(text)}
{:else}
	{text}
{/if}
