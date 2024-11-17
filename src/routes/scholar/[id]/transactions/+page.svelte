<script lang="ts">
	import Feedback from '$lib/components/Feedback.svelte';
	import Page from '$lib/components/Page.svelte';
	import Transactions from '$lib/components/Transactions.svelte';

	let { data } = $props();
	let { scholar, transactions } = $derived(data);
</script>

{#if scholar && transactions}
	<Page title={scholar.name ?? scholar.email ?? 'anonymous'} subtitle="Transactions">
		<p>These are all {transactions.length} transactions for this scholar.</p>
		<Transactions {transactions} />
	</Page>
{:else if scholar === null}
	<h1>Oops.</h1>
	<Feedback error>Unknown scholar.</Feedback>
{:else if transactions === null}
	<h1>Oops.</h1>
	<Feedback error>Unknown scholar.</Feedback>
{/if}
