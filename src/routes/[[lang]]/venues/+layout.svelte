<script lang="ts">
	import ContextBar from '#lib/components/ContextBar.svelte';
	import { venuesBar } from '#lib/data/contextBar.js';
	import { getAuth } from '#routes/Auth.svelte.js';
	import { getLocaleContext } from '#routes/Contexts.js';
	import type { Snippet } from 'svelte';

	let { children }: { children: Snippet } = $props();

	const auth = getAuth();
	const locale = getLocaleContext();
</script>

<ContextBar
	bar={venuesBar(locale(), auth().isAuthenticated())}
	menu={(l) => l.header.context.menu}
/>
{@render children()}
