<script lang="ts">
	import { getDB } from '$lib/data/Database';
	import type { TransactionID } from '$lib/types/Transaction';
	import Feedback from './Feedback.svelte';
	import Transaction from './Transaction.svelte';
	import type { default as Trans } from '$lib/types/Transaction';

	export let id: TransactionID | Trans;

	const db = getDB();
</script>

{#if typeof id === 'string'}
	{#await db.getTransaction(id)}
		...
	{:then transaction}
		{#if transaction}
			<Transaction {transaction} />
		{:else}
			<Feedback error>Unknown transaction.</Feedback>
		{/if}
	{:catch}
		<Feedback error>Couldn't load transaction.</Feedback>
	{/await}
{:else}
	<Transaction transaction={id} />
{/if}
