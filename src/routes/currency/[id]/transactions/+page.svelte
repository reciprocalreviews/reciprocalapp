<script lang="ts">
	import Feedback from '$lib/components/Feedback.svelte';
	import Page from '$lib/components/Page.svelte';
	import Transactions from '$lib/components/Transactions.svelte';
	import { getDB } from '$lib/data/CRUD';

	let { data } = $props();
	let { currency, transactions, count, venues } = $derived(data);

	const db = getDB();
</script>

{#if currency && transactions && venues && count}
	<Page title={currency.name} breadcrumbs={[[`/currency/${currency.id}`, currency.name]]}>
		{#snippet subtitle()}Transactions{/snippet}
		<p>These are all {count} transactions for this currency visible to you.</p>
		<Transactions
			{transactions}
			{count}
			{venues}
			currencies={[currency]}
			more={async (page) => db().getCurrencyTransactions(currency.id, page)}
			testid="currency-transaction"
		/>
	</Page>
{:else if currency === null}
	<h1>Oops.</h1>
	<Feedback error>Unknown scholar.</Feedback>
{:else if transactions === null}
	<h1>Oops.</h1>
	<Feedback error>Unknown scholar.</Feedback>
{/if}
