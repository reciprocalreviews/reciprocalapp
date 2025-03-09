<script lang="ts">
	import type { CurrencyRow, TransactionRow, VenueRow } from '$data/types';
	import { getDB } from '$lib/data/CRUD';
	import { getAuth } from '../../routes/Auth.svelte';
	import { handle } from '../../routes/feedback.svelte';
	import Button from './Button.svelte';
	import Dialog from './Dialog.svelte';
	import Feedback from './Feedback.svelte';
	import Note from './Note.svelte';
	import ScholarLink from './ScholarLink.svelte';
	import Status from './Status.svelte';
	import Table from './Table.svelte';
	import TextField from './TextField.svelte';
	import Tokens from './Tokens.svelte';
	import VenueLink from './VenueLink.svelte';

	let {
		transactions,
		venues,
		currencies
	}: {
		transactions: TransactionRow[];
		venues: VenueRow[];
		currencies: CurrencyRow[] | null;
	} = $props();

	// Get the current user
	const db = getDB();
	const auth = getAuth();

	// Editable if the user is the scholar being viewed.
	let userid = $derived(auth.getUserID());

	let showCancel = $state(false);
	let cancelReason = $state('');
</script>

{#snippet row(transaction: TransactionRow)}
	{@const currency = currencies?.find((c) => c.id === transaction.currency)}
	{@const editable =
		transaction.status === 'proposed' &&
		userid !== null &&
		(transaction.from_scholar === userid ||
			(transaction.from_venue !== null &&
				venues.find((v) => v.id === transaction.from_venue)?.editors.includes(userid)) ||
			currency?.minters.includes(userid))}
	<tr>
		<td>
			<Status good={transaction.status === 'approved'}>{transaction.status}</Status>
		</td>
		<td
			>{#if transaction.tokens === null}unknown{:else}<Tokens
					amount={transaction.tokens.length}
					{currency}
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
		<td><Note>{transaction.purpose}</Note></td>
		<td>
			{#if editable}
				<div class="column">
					<!-- If the authenticated scholar is a minter of the given currency, or the giver, then show an approve button -->
					<Button
						tip="Approve this proposed transaction"
						action={() => handle(db.approveTransaction(userid, transaction.id))}>Approve</Button
					>
					<Button
						tip="Cancel this proposed transaction"
						active={!showCancel}
						action={() => (showCancel = true)}>Cancel…</Button
					>
					<Dialog bind:show={showCancel}>
						<p>Indicate a reason and we'll append it to the transaction message.</p>
						<TextField bind:text={cancelReason} placeholder="Reason for cancellation" />
						<Button
							tip="Cancel this proposed transaction"
							warn="Cancel"
							active={cancelReason.length > 0}
							action={async () => {
								await handle(
									db.cancelTransaction(
										transaction.id,
										transaction.purpose.trim() + ' - ' + cancelReason
									)
								);
								showCancel = false;
							}}>Cancel this transaction</Button
						>
					</Dialog>
				</div>
			{/if}
		</td>
	</tr>
{/snippet}

{#if transactions.length === 0}
	<Feedback>No transactions yet.</Feedback>
{:else}
	<Table full>
		{#snippet header()}
			<th>Status</th>
			<th>Tokens</th>
			<th>From</th>
			<th>To</th>
			<th>Purpose</th>
			<th>Actions</th>
		{/snippet}
		{#each transactions.sort((a, b) => new Date(b.created).getTime() - new Date(a.created).getTime()) as transaction}
			{@render row(transaction)}
		{/each}
	</Table>
{/if}

<style>
	th,
	td {
		font-size: var(--small-font-size);
	}

	.column {
		display: flex;
		flex-direction: column;
		gap: var(--spacing);
	}
</style>
