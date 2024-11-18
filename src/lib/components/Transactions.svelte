<script lang="ts">
	import type { TransactionRow, VenueID } from '$data/types';
	import Feedback from './Feedback.svelte';
	import ScholarLink from './ScholarLink.svelte';
	import Table from './Table.svelte';
	import Tag from './Tag.svelte';
	import Tokens from './Tokens.svelte';
	import VenueLink from './VenueLink.svelte';

	let {
		transactions,
		venues
	}: {
		transactions: TransactionRow[];
		venues: { id: VenueID; title: string }[];
	} = $props();
</script>

{#snippet row(transaction: TransactionRow)}
	<tr>
		<td
			>{#if transaction.tokens === null}unknown{:else}<Tokens
					amount={transaction.tokens.length}
				/>{/if}</td
		>
		<td
			>{#if transaction.from_scholar}<ScholarLink
					id={transaction.from_scholar}
				/>{:else if transaction.from_venue}<VenueLink
					id={transaction.from_venue}
					name={venues.find((v) => v.id === transaction.from_venue)?.title ?? 'unknkown venue'}
				></VenueLink>{/if}</td
		>
		<td
			>{#if transaction.to_scholar}<ScholarLink
					id={transaction.to_scholar}
				/>{:else if transaction.to_venue}<VenueLink
					id={transaction.to_venue}
					name={venues.find((v) => v.id === transaction.to_venue)?.title ?? 'unknkown venue'}
				></VenueLink>{/if}</td
		>
		<td>{transaction.purpose}</td>
	</tr>
{/snippet}

{#if transactions.length === 0}
	<Feedback>No transactions yet.</Feedback>
{:else}
	<Table>
		<tr>
			<th>Tokens</th>
			<th>From</th>
			<th>To</th>
			<th>Purpose</th>
		</tr>
		{#each transactions.sort((a, b) => new Date(b.created).getTime() - new Date(a.created).getTime()) as transaction}
			{@render row(transaction)}
		{/each}
	</Table>
{/if}
