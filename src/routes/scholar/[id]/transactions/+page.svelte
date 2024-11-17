<script lang="ts">
	import Feedback from '$lib/components/Feedback.svelte';
	import { getDB } from '$lib/data/CRUD';
	import Page from '$lib/components/Page.svelte';
	import Transactions from '$lib/components/Transactions.svelte';

	let { data } = $props();
	let { scholar, transactions } = $derived(data);

	let db = getDB();
</script>

{#if scholar && transactions}
	<Page title={scholar.name ?? scholar.email ?? 'anonymous'} subtitle="Transactions">
		<p>{transactions.length} transactions.</p>
		<Transactions {transactions} />
	</Page>
{:else if scholar === null}
	<h1>Oops.</h1>
	<Feedback error>Unknown scholar.</Feedback>
{:else if transactions === null}
	<h1>Oops.</h1>
	<Feedback error>Unknown scholar.</Feedback>
{/if}
