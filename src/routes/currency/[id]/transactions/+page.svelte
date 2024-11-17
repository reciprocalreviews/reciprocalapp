<script lang="ts">
	import Feedback from '$lib/components/Feedback.svelte';
	import Page from '$lib/components/Page.svelte';
	import Transactions from '$lib/components/Transactions.svelte';

	let { data } = $props();
	let { currency, transactions } = $derived(data);
</script>

{#if currency && transactions}
	<Page title={currency.name} subtitle="Transactions">
		<p>These are all {transactions.length} transactions for this currency.</p>
		<Transactions {transactions} />
	</Page>
{:else if currency === null}
	<h1>Oops.</h1>
	<Feedback error>Unknown scholar.</Feedback>
{:else if transactions === null}
	<h1>Oops.</h1>
	<Feedback error>Unknown scholar.</Feedback>
{/if}
