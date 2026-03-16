<script lang="ts">
	import type LocaleText from '$lib/locales/Locale';
	import Text from '$lib/locales/Text.svelte';

	interface Props {
		icon: string;
		text: string | ((locale: LocaleText) => string | string[]);
		id?: string;
	}

	let { icon, id, text }: Props = $props();
</script>

<h2 {id}>
	<span>{icon}</span>
	{#if typeof text === 'string'}{text}{:else}<Text path={text} />{/if}
</h2>

<style>
	h2 {
		display: flex;
		gap: 0.25rem;
		align-items: baseline;
	}

	span {
		font-family: 'Noto Emoji', 'Josefin Sans', sans-serif;
		color: var(--border-color);
	}
</style>
