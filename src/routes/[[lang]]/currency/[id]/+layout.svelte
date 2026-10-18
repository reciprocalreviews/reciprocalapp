<script lang="ts">
	import { page } from '$app/state';
	import ContextBar from '#lib/components/ContextBar.svelte';
	import { currencyBar } from '#lib/data/contextBar.js';
	import { reloadOnChanges } from '#lib/data/SupabaseRealtime.js';
	import { getLocaleContext } from '$routes/Contexts';

	let { data, children } = $props();

	const locale = getLocaleContext();

	const currencyID = page.params.id;

	// Invalidate this page when the currency or its transactions change
	reloadOnChanges('currency_changes', [
		{ table: 'currencies', filter: `id=eq.${currencyID}` },
		{ table: 'transactions', filter: `currency=eq.${currencyID}` }
	]);
</script>

{#if data.currency}
	<ContextBar bar={currencyBar(data.currency, locale())} menu={(l) => l.header.context.menu} />
{/if}
{@render children()}
