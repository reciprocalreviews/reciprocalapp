<script lang="ts">
	import Feedback from '#lib/components/Feedback.svelte';
	import Page from '#lib/components/Page.svelte';
	import Paragraph from '#lib/components/Paragraph.svelte';
	import Transactions from '#lib/components/Transactions.svelte';
	import { getDB } from '#lib/data/CRUD.js';

	let { data } = $props();
	let { scholar, transactions, count, venues, currencies } = $derived(data);

	const db = getDB();
</script>

{#if scholar && transactions && venues && currencies && count !== null}
	<!-- Titled by what the page is. The scholar is named by the breadcrumb back to them, and
	     in the tab. -->
	<Page
		title={(l) => l.page.scholarTransactions.title}
		context={scholar.name ?? scholar.email ?? undefined}
	>
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
	<Page title={(l) => l.page.error.title}>
		<Feedback error text={(l) => l.view.transactions.feedback.notLoaded}></Feedback>
	</Page>
{/if}
