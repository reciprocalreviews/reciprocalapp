<script lang="ts">
	import { page } from '$app/state';
	import { loginHref } from '#lib/auth/next.js';
	import { getLocaleContext } from '$routes/Contexts';
	import { marked } from 'marked';
	import type { Html } from './html';
	import type LocaleText from './Locale';
	import interpolate from './interpolate';

	let {
		path,
		markdown = false,
		inputs = {}
	}: {
		path: string | ((locale: LocaleText) => string | string[]);
		markdown?: boolean;
		/** Substituted into `{name}` placeholders. Plain strings are escaped when
		 * `markdown` is set, since that path renders through `{@html}`; pass `html()`
		 * from ./html for a value that is deliberately markup. */
		inputs?: Record<string, string | Html>;
	} = $props();

	const locale = getLocaleContext();

	// Construct the text from the locale file. The substitution rules themselves
	// live in ./interpolate so they can be tested directly — this is the one
	// place every user-visible string in the app passes through.
	const text = $derived.by(() => {
		const loc = locale();
		return interpolate(
			typeof path === 'string' ? path : path(loc),
			loc.shorthand,
			inputs,
			markdown
		);
	});
</script>

{#if markdown}
	<!-- Every "[Log in](/login)" in the locale file comes back to the page it was read on, so
	     the strings needn't each know where they are. -->
	{@html marked(text, { async: false }).replaceAll(
		'href="/login"',
		`href="${loginHref(page.url)}"`
	)}
{:else}
	{text}
{/if}
