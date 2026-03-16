<script lang="ts">
	import { page } from '$app/state';
	import { reloadOnChanges } from '$lib/data/SupabaseRealtime';

	let { children } = $props();

	const currencyID = page.params.id;

	// Invalidate this page when the currency or its transactions change
	reloadOnChanges('currency_changes', [
		{ table: 'currencies', filter: `id=eq.${currencyID}` },
		{ table: 'transactions', filter: `currency=eq.${currencyID}` }
	]);
</script>

{@render children()}
