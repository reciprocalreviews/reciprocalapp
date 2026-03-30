<script lang="ts">
	import type Locale from '$lib/locales/Locale';
	import Text from '$lib/locales/Text.svelte';

	interface Props {
		text: (l: Locale) => string;
		inputs?: Record<string, string>;
	}

	const { text, inputs = {} }: Props = $props();
</script>

<p><Text markdown path={text} {inputs} /></p>
