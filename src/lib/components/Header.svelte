<script lang="ts">
	import type LocaleText from '$lib/locales/Locale';
	import Text from '$lib/locales/Text.svelte';

	/** A lead paragraph, which is styled larger and italicized. */
	let { path, sub = false }: { sub: boolean; path: (l: LocaleText) => string | string[] } =
		$props();
</script>

{#if sub}
	<h2><Text markdown {path} /></h2>
{:else}
	<h1><Text markdown {path} /></h1>
{/if}
