<script lang="ts">
	import Circle from '$lib/components/Circle.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import { TokenLabel } from '$lib/components/Labels';
	import Page from '$lib/components/Page.svelte';
	import Transactions from '$lib/components/Transactions.svelte';
	import { getDB } from '$lib/data/CRUD';

	let { data } = $props();
	let { currency, transactions, count, venues } = $derived(data);

	const db = getDB();
</script>

{#if currency && transactions && venues && count}
	<Page
		icon={TokenLabel}
		title={currency.name}
		breadcrumbs={[[`/currency/${currency.id}`, `${TokenLabel} ${currency.name}`]]}
	>
		{#snippet subtitle()}Transactions{/snippet}
		<p>There are <Circle icon={count}></Circle> transactions with this currency visible to you.</p>
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
	<Feedback error>Unknown currency.</Feedback>
{:else if transactions === null}
	<h1>Oops.</h1>
	<Feedback error>Unable to load transactions.</Feedback>
{/if}
