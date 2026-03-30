<script lang="ts">
	import Feedback from '$lib/components/Feedback.svelte';
	import { ErrorLabel, ScholarLabel } from '$lib/components/Labels.js';
	import Page from '$lib/components/Page.svelte';
	import Paragraph from '$lib/components/Paragraph.svelte';
	import Transactions from '$lib/components/Transactions.svelte';
	import { getDB } from '$lib/data/CRUD.js';
	import Text from '$lib/locales/Text.svelte';

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
		{#snippet subtitle()}<Text path={(l) => l.page.scholarTransactions.subtitle} />{/snippet}
		<Paragraph
			text={(l) => l.page.scholarTransactions.paragraph.count}
			inputs={{ count: count.toString() }}
		/>
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
