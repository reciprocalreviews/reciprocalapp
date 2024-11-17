<script lang="ts">
	import type { TransactionRow } from '$data/types';
	import Feedback from './Feedback.svelte';
	import ScholarLink from './ScholarLink.svelte';
	import Table from './Table.svelte';
	import Tag from './Tag.svelte';
	import Tokens from './Tokens.svelte';
	import VenueLink from './VenueLink.svelte';

	let {
		transactions
	}: {
		transactions: TransactionRow[];
	} = $props();
</script>

{#snippet row(transaction: TransactionRow)}
	<tr>
		<td><Tag>{transaction.purpose}</Tag></td>
		<td><Tokens amount={transaction.tokens.length} /></td>
		<td
			>{#if transaction.from_scholar}<ScholarLink
					id={transaction.from_scholar}
				/>{:else if transaction.from_venue}<VenueLink id={transaction.from_venue}
				></VenueLink>{/if}</td
		>
		<td
			>{#if transaction.to_scholar}<ScholarLink
					id={transaction.to_scholar}
				/>{:else if transaction.to_venue}<VenueLink id={transaction.to_venue}></VenueLink>{/if}</td
		>
	</tr>
{/snippet}

{#if transactions.length === 0}
	<Feedback>No transactions yet.</Feedback>
{:else}
	<Table>
		<tr>
			<th>Purpose</th>
			<th>Tokens</th>
			<th>From</th>
			<th>To</th>
		</tr>
		{#each transactions.sort((a, b) => new Date(b.created).getTime() - new Date(a.created).getTime()) as transaction}
			<tr>
				{@render row(transaction)}
			</tr>
		{/each}
	</Table>
{/if}
