<script lang="ts">
	import { page } from '$app/stores';
	import type { CurrencyRow, TransactionRow, VenueID } from '$data/types';
	import { getDB } from '$lib/data/CRUD';
	import { getAuth } from '../../routes/Auth.svelte';
	import { handle } from '../../routes/feedback.svelte';
	import Button from './Button.svelte';
	import Feedback from './Feedback.svelte';
	import ScholarLink from './ScholarLink.svelte';
	import Status from './Status.svelte';
	import Table from './Table.svelte';
	import Tokens from './Tokens.svelte';
	import VenueLink from './VenueLink.svelte';

	let {
		transactions,
		venues,
		currency = undefined
	}: {
		transactions: TransactionRow[];
		venues: { id: VenueID; title: string }[];
		currency?: CurrencyRow | undefined;
	} = $props();

	// Get the current user
	const db = getDB();
	const auth = getAuth();

	// Editable if the user is the scholar being viewed.
	let userid = $derived(auth.getUserID());
	let editable = $derived(
		userid !== null && currency !== undefined && currency.minters.includes(userid)
	);
</script>

{#snippet row(transaction: TransactionRow)}
	<tr>
		<td>
			<Status good={transaction.status === 'approved'}>{transaction.status}</Status>
		</td>
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
		<td>
			{#if transaction.status === 'proposed' && editable && userid}<Button
					tip="Approve this proposed transaction"
					action={() => handle(db.approveTransaction(userid, transaction.id))}>Approve</Button
				>{/if}
		</td>
	</tr>
{/snippet}

{#if transactions.length === 0}
	<Feedback>No transactions yet.</Feedback>
{:else}
	<Table>
		<tr>
			<th>Status</th>
			<th>Tokens</th>
			<th>From</th>
			<th>To</th>
			<th>Purpose</th>
			<th></th>
		</tr>
		{#each transactions.sort((a, b) => new Date(b.created).getTime() - new Date(a.created).getTime()) as transaction}
			{@render row(transaction)}
		{/each}
	</Table>
{/if}
