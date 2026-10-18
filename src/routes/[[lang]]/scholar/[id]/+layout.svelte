<script lang="ts">
	import { page } from '$app/state';
	import ContextBar from '#lib/components/ContextBar.svelte';
	import { scholarBar } from '#lib/data/contextBar.js';
	import { reloadOnChanges } from '#lib/data/SupabaseRealtime.js';
	import { getLocaleContext } from '$routes/Contexts';

	let { data, children } = $props();

	const locale = getLocaleContext();

	// Reload when the scholar data changes.
	reloadOnChanges('scholar_changes', [{ table: 'scholars', filter: `id=eq.${page.params.id}` }]);
</script>

{#if data.scholar}
	<ContextBar bar={scholarBar(data.scholar, locale())} menu={(l) => l.header.context.menu} />
{/if}
{@render children()}
