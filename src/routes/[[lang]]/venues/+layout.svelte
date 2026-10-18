<script lang="ts">
	import ContextBar from '#lib/components/ContextBar.svelte';
	import { venuesBar } from '#lib/data/contextBar.js';
	import { getAuth } from '$routes/Auth.svelte';
	import { getLocaleContext } from '$routes/Contexts';
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
