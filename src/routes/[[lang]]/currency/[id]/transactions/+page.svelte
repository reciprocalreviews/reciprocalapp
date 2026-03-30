<script lang="ts">
	import Feedback from '$lib/components/Feedback.svelte';
	import { ErrorLabel, TokenLabel } from '$lib/components/Labels';
	import Page from '$lib/components/Page.svelte';
	import Paragraph from '$lib/components/Paragraph.svelte';
	import Transactions from '$lib/components/Transactions.svelte';
	import { getDB } from '$lib/data/CRUD';
	import Text from '$lib/locales/Text.svelte';

	let { data } = $props();
	let { currency, transactions, count, venues } = $derived(data);

	const db = getDB();
</script>

{#if currency && transactions && venues && count !== null}
	<Page
		icon={TokenLabel}
		title={currency.name}
		breadcrumbs={[[`/currency/${currency.id}`, `${TokenLabel} ${currency.name}`]]}
	>
		{#snippet subtitle()}<Text path={(l) => l.page.currencyTransactions.subtitle} />{/snippet}

		<Paragraph
			text={(l) => l.page.currencyTransactions.paragraph.count}
			inputs={{ count: count.toString() }}
		/>

		<Transactions
			{transactions}
			{count}
			{venues}
			currencies={[currency]}
			more={async (page) => db().getCurrencyTransactions(currency.id, page)}
			// Currency transactions are never a debit, as there's no perspective.
			isDebit={() => false}
			testid="currency-transaction"
		/>
	</Page>
{:else if currency === null || transactions === null}
	<Page icon={ErrorLabel} title={(l) => l.page.error.title} breadcrumbs={[]}>
		<Feedback error text={(l) => l.page.currency.feedback.notLoaded} />
	</Page>
{/if}
