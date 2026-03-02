<script lang="ts">
	import Circle from '$lib/components/Circle.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import { ScholarLabel } from '$lib/components/Labels.js';
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
		title={scholar.name ?? scholar.email ?? 'anonymous'}
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
		/>
	</Page>
{:else if scholar === null}
	<h1>Oops.</h1>
	<Feedback error>Unknown scholar.</Feedback>
{:else if transactions === null}
	<h1>Oops.</h1>
	<Feedback error>Unable to load transactions for this scholar.</Feedback>
{/if}
