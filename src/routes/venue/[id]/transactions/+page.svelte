<script lang="ts">
	import Feedback from '$lib/components/Feedback.svelte';
	import { getDB } from '$lib/data/CRUD';
	import Page from '$lib/components/Page.svelte';
	import Transactions from '$lib/components/Transactions.svelte';

	let { data } = $props();
	let { venue, transactions } = $derived(data);
</script>

{#if venue && transactions}
	<Page title={venue.title} subtitle="Transactions">
		<p>{transactions.length} transactions.</p>
		<Transactions {transactions} />
	</Page>
{:else if venue === null}
	<h1>Oops.</h1>
	<Feedback error>Unknown scholar.</Feedback>
{:else if transactions === null}
	<h1>Oops.</h1>
	<Feedback error>Unknown scholar.</Feedback>
{/if}
