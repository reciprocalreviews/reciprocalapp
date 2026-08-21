<script lang="ts">
	import { getLocaleContext } from '$routes/Contexts';
	import { marked } from 'marked';
	import type LocaleText from './Locale';
	import interpolate from './interpolate';

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

	// Construct the text from the locale file. The substitution rules themselves
	// live in ./interpolate so they can be tested directly — this is the one
	// place every user-visible string in the app passes through.
	const text = $derived.by(() => {
		const loc = locale();
		return interpolate(typeof path === 'string' ? path : path(loc), loc.shorthand, inputs);
	});
</script>

{#if markdown}
	{@html marked(text)}
{:else}
	{text}
{/if}
