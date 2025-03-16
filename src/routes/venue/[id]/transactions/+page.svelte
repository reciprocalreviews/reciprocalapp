<script lang="ts">
	import Circle from '$lib/components/Circle.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import Page from '$lib/components/Page.svelte';
	import Transactions from '$lib/components/Transactions.svelte';

	let { data } = $props();
	let { venue, transactions, venues, currencies } = $derived(data);
</script>

{#if venue && transactions && venues}
	<Page title={venue.title} breadcrumbs={[[`/venue/${venue.id}`, venue.title]]}>
		{#snippet subtitle()}Transactions{/snippet}
		<p>These are all <Circle icon={transactions.length}></Circle> transactions for this venue.</p>
		<Transactions {transactions} {venues} {currencies} />
	</Page>
{:else if venue === null}
	<h1>Oops.</h1>
	<Feedback error>Unknown scholar.</Feedback>
{:else if transactions === null}
	<h1>Oops.</h1>
	<Feedback error>Unknown scholar.</Feedback>
{/if}
