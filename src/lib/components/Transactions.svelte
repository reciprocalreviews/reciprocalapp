<script lang="ts">
	import type { CurrencyRow, TransactionRow, VenueRow } from '$data/types';
	import { getLocaleContext } from '$routes/Contexts';
	import { SvelteMap } from 'svelte/reactivity';
	import { getAuth } from '../../routes/Auth.svelte';
	import { handle } from '../../routes/feedback.svelte';
	import Button from './Button.svelte';
	import Feedback from './Feedback.svelte';
	import Note from './Note.svelte';
	import ScholarLink from './ScholarLink.svelte';
	import Status from './Status.svelte';
	import Table from './Table.svelte';
	import Tokens from './Tokens.svelte';
	import TransactionActions from './TransactionActions.svelte';
	import VenueLink from './VenueLink.svelte';

	let {
		transactions,
		count,
		venues,
		currencies,
		testid,
		more,
		isDebit
	}: {
		transactions: TransactionRow[];
		venues: VenueRow[];
		currencies: CurrencyRow[];
		testid?: string;
		count: number;
		more: (page: number) => Promise<{ data: TransactionRow[] | null; error: any }>;
		/** Should return true if the row should be treated as a debit */
		isDebit: (transaction: TransactionRow) => boolean;
	} = $props();

	// Get the current user
	const auth = getAuth();
	const locale = getLocaleContext();

	// Editable if the user is the scholar being viewed.
	let userid = $derived(auth().getUserID());


	// The loaded transactions, starting with the ones passed in as props.
	// svelte-ignore state_referenced_locally
	let transactionsByPage = $state(new SvelteMap([[0, transactions]]));
	let page = $state(0);

	// Re-sync when the prop changes (e.g. after invalidateAll() from a realtime event).
	$effect(() => {
		transactionsByPage = new SvelteMap([[0, transactions]]);
		page = 0;
	});

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
			currency?.minters.includes(userid)) &&
		// Anti-self-dealing: hide approval from recipients.
		transaction.to_scholar !== userid &&
		!(
			transaction.to_venue !== null &&
			venues.find((v) => v.id === transaction.to_venue)?.admins.includes(userid)
		)}
	<tr data-testid={testid + '-' + index}>
		<td>
			<Status
				good={transaction.status === 'approved'}
				label={(l) =>
					transaction.status === 'approved'
						? l.view.transactions.status.approved
						: transaction.status === 'declined'
							? l.view.transactions.status.declined
							: l.view.transactions.status.proposed}
			/>
		</td>
		<td><Tokens amount={transaction.tokens.length} debit={isDebit(transaction)} {currency} /></td>
		<td>
			<ScholarLink size="extra-small" id={transaction.creator} />
		</td>
		<td
			>{#if transaction.from_scholar}<ScholarLink
					size="extra-small"
					id={transaction.from_scholar}
				/>{:else if transaction.from_venue}<VenueLink
					size="extra-small"
					id={transaction.from_venue}
					name={venues.find((v) => v.id === transaction.from_venue)?.title ??
						locale().view.transactions.error.unknownVenue}
				></VenueLink>{:else}<em>{locale().view.transactions.cell.minted}</em>{/if}</td
		>
		<td
			>{#if transaction.to_scholar}<ScholarLink
					size="extra-small"
					id={transaction.to_scholar}
				/>{:else if transaction.to_venue}<VenueLink
					size="extra-small"
					id={transaction.to_venue}
					name={venues.find((v) => v.id === transaction.to_venue)?.title ??
						locale().view.transactions.error.unknownVenue}
				></VenueLink>{/if}</td
		>
		<td>
			<Note path={() => transaction.purpose} />
			{#if transaction.status === 'declined' && transaction.decline_reason !== null}
				<div class="decline">
					<em>Declined{#if transaction.decliner}
							by <ScholarLink id={transaction.decliner} />{/if}:</em
					>
					<Note path={() => transaction.decline_reason ?? ''} />
				</div>
			{/if}
		</td>
		<td>
			{#if editable && userid !== null}
				<TransactionActions {transaction} {index} {userid} testid={testid ?? ''} />
			{:else if proposed}
				<em>{locale().view.transactions.cell.pendingApproval}</em>
			{:else}
				—
			{/if}
		</td>
	</tr>
{/snippet}

{#if allTransactions.length === 0}
	<Feedback testid="no-transactions" text={(l) => l.view.transactions.feedback.noTransactions} />
{:else}
	<Table full>
		{#snippet header()}
			<th>{locale().view.transactions.headers.status}</th>
			<th>{locale().view.transactions.headers.tokens}</th>
			<th>{locale().view.transactions.headers.scholar}</th>
			<th>{locale().view.transactions.headers.from}</th>
			<th>{locale().view.transactions.headers.to}</th>
			<th>{locale().view.transactions.headers.purpose}</th>
			<th>{locale().view.transactions.headers.actions}</th>
		{/snippet}
		{#each allTransactions.sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime()) as transaction, index}
			{@render row(transaction, index)}
		{/each}
		<tr>
			<td colspan="100">
				{#if allTransactions.length >= count}
					{locale().view.transactions.cell.allLoaded}
				{:else}
					<Button
						strings={(l) => l.view.transactions.button.loadMore}
						action={() => loadMore()}
						active={!loading}
						>{#if loading}…{/if}</Button
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

	.decline {
		margin-top: var(--spacing-half);
		font-size: var(--extra-small-font-size);
	}
</style>
