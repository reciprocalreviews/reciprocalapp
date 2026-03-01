<script lang="ts">
	import type { CurrencyRow, TransactionRow, VenueRow } from '$data/types';
	import { getDB } from '$lib/data/CRUD';
	import { SvelteMap } from 'svelte/reactivity';
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
		count,
		venues,
		currencies,
		testid,
		more
	}: {
		transactions: TransactionRow[];
		venues: VenueRow[];
		currencies: CurrencyRow[];
		testid?: string;
		count: number;
		more: (page: number) => Promise<{ data: TransactionRow[] | null; error: any }>;
	} = $props();

	// Get the current user
	const db = getDB();
	const auth = getAuth();

	// Editable if the user is the scholar being viewed.
	let userid = $derived(auth.getUserID());

	let showCancel = $state(false);
	let cancelReason = $state('');

	// The loaded transactions, starting with the ones passed in as props.
	// svelte-ignore state_referenced_locally
	let transactionsByPage = $state(new SvelteMap([[0, transactions]]));
	let page = $state(0);
	let allTransactions = $derived(Array.from(transactionsByPage.values()).flat());

	let loading = $state(false);
	async function loadMore() {
		// Don't load more if we've already loaded all transactions.
		if (allTransactions.length >= count) return;
		loading = true;
		page = page + 1;
		const { data: transactions, error } = await more(page);
		if (error || transactions === null) {
			handle(error);
			page = page - 1;
		} else {
			transactionsByPage.set(page, transactions);
		}
		loading = false;
	}
</script>

{#snippet row(transaction: TransactionRow, index: number)}
	{@const currency = currencies?.find((c) => c.id === transaction.currency)}
	{@const proposed = transaction.status === 'proposed'}
	{@const editable =
		proposed &&
		userid !== null &&
		(transaction.from_scholar === userid ||
			(transaction.from_venue !== null &&
				venues.find((v) => v.id === transaction.from_venue)?.admins.includes(userid)) ||
			currency?.minters.includes(userid))}
	<tr data-testid={testid + '-' + index}>
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
					name={venues.find((v) => v.id === transaction.from_venue)?.title ?? 'unknown venue'}
				></VenueLink>{/if}</td
		>
		<td
			>{#if transaction.to_scholar}<ScholarLink
					id={transaction.to_scholar}
				/>{:else if transaction.to_venue}<VenueLink
					id={transaction.to_venue}
					name={venues.find((v) => v.id === transaction.to_venue)?.title ?? 'unknown venue'}
				></VenueLink>{/if}</td
		>
		<td><Note>{transaction.purpose}</Note></td>
		<td>
			{#if editable}
				<div class="column">
					<!-- If the authenticated scholar is a minter of the given currency, or the giver, then show an approve button -->
					<Button
						tip="Approve this proposed transaction"
						action={() => handle(db().approveTransaction(userid, transaction.id))}>Approve</Button
					>
					<Button
						tip="Cancel this proposed transaction"
						active={!showCancel}
						action={() => (showCancel = true)}>Cancel…</Button
					>
					<Dialog bind:show={showCancel}>
						<p>Indicate a reason and we'll append it to the transaction message.</p>
						<TextField
							label="Reason"
							bind:text={cancelReason}
							placeholder="Reason for cancellation"
						/>
						<Button
							tip="Cancel this proposed transaction"
							warn="Cancel"
							active={cancelReason.length > 0}
							action={async () => {
								await handle(
									db().cancelTransaction(
										transaction.id,
										transaction.purpose.trim() + ' - ' + cancelReason
									)
								);
								showCancel = false;
							}}>Cancel this transaction</Button
						>
					</Dialog>
				</div>
			{:else if proposed}
				<em>Pending approval by editor or minter.</em>
			{:else}
				—
			{/if}
		</td>
	</tr>
{/snippet}

{#if allTransactions.length === 0}
	<Feedback testid="no-transactions">No transactions.</Feedback>
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
		{#each allTransactions.sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime()) as transaction, index}
			{@render row(transaction, index)}
		{/each}
		<tr>
			<td colspan="100">
				{#if allTransactions.length >= count}
					All transactions loaded.
				{:else}
					<Button tip="Load more transactions" action={() => loadMore()} active={!loading}
						>{#if loading}Loading…{:else}Load more transactions...{/if}</Button
					>
				{/if}
			</td>
		</tr>
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
