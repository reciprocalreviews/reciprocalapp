<script lang="ts">
	import Feedback from '$lib/components/Feedback.svelte';
	import Page from '$lib/components/Page.svelte';
	import Transactions from '$lib/components/Transactions.svelte';

	let { data } = $props();
	let { scholar, transactions, venues } = $derived(data);
</script>

{#if scholar && transactions && venues}
	<Page
		title={scholar.name ?? scholar.email ?? 'anonymous'}
		breadcrumbs={[
			[`/${scholar.id}`, scholar.name ?? scholar.orcid ?? scholar.email ?? 'anonymous']
		]}
	>
		{#snippet subtitle()}Transactions{/snippet}
		<p>These are all {transactions.length} transactions for this scholar.</p>
		<Transactions {transactions} {venues} />
	</Page>
{:else if scholar === null}
	<h1>Oops.</h1>
	<Feedback error>Unknown scholar.</Feedback>
{:else if transactions === null}
	<h1>Oops.</h1>
	<Feedback error>Unknown scholar.</Feedback>
{/if}
