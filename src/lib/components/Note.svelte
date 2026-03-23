<script lang="ts">
	import Text from '$lib/locales/Text.svelte';
	import type LocaleText from '$lib/locales/Locale';

	let { path }: { path: (l: LocaleText) => string } = $props();
</script>

<div><Text {path} markdown /></div>

<style>
	div {
		font-size: var(--small-font-size);
		font-style: italic;
	}
</style>
