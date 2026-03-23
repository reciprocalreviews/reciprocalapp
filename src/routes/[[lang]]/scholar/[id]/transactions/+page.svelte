<script lang="ts">
	import Circle from '$lib/components/Circle.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import { ErrorLabel, ScholarLabel } from '$lib/components/Labels.js';
	import Page from '$lib/components/Page.svelte';
	import Transactions from '$lib/components/Transactions.svelte';
	import { getDB } from '$lib/data/CRUD.js';

	let { data } = $props();
	let { scholar, transactions, count, venues, currencies } = $derived(data);

	const db = getDB();
</script>

{#if scholar && transactions && venues && currencies && count !== null}
	<Page
		icon={ScholarLabel}
		title={scholar.name ?? scholar.email ?? ((l) => l.page.scholar.title)}
		breadcrumbs={[
			[`/scholar/${scholar.id}`, scholar.name ?? scholar.orcid ?? scholar.email ?? 'anonymous']
		]}
	>
		{#snippet subtitle()}Transactions{/snippet}
		<p>There are <Circle icon={count}></Circle> transactions visible to you.</p>
		<Transactions
			{transactions}
			{venues}
			{currencies}
			testid="scholar-transaction"
			{count}
			more={async (page) => db().getScholarTransactions(scholar.id, page)}
			isDebit={(transaction) => transaction.from_scholar === scholar.id}
		/>
	</Page>
{:else}
	<Page icon={ErrorLabel} title={(l) => l.page.error.title} breadcrumbs={[]}>
		<Feedback error text={(l) => l.view.transactions.feedback.notLoaded}></Feedback>
	</Page>
{/if}
