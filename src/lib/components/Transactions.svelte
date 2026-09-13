<script lang="ts">
	import type { CurrencyRow, VenueRow } from '$data/types';
	import type { TransactionListRow } from '$lib/data/SupabaseCRUD.svelte';
	import { getLocaleContext } from '$routes/Contexts';
	import { getAuth } from '../../routes/Auth.svelte';
	import { addError } from '../../routes/feedback.svelte';
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
		transactions: TransactionListRow[];
		venues: VenueRow[];
		currencies: CurrencyRow[];
		testid?: string;
		count: number;
		more: (page: number) => Promise<{ data: TransactionListRow[] | null; error: any }>;
		/** Should return true if the row should be treated as a debit */
		isDebit: (transaction: TransactionListRow) => boolean;
	} = $props();

	// Get the current user
	const auth = getAuth();
	const locale = getLocaleContext();

	// Editable if the user is the scholar being viewed.
	let userid = $derived(auth().getUserID());

	// Page 0 is NOT cached: it is the `transactions` prop, rendered live. Caching it
	// made a refetch that changed only a row's mutable fields — the status an approval
	// flips, the decliner and reason a decline records — invisible, because the cache
	// was keyed on the row ids and those don't change. The Approve button therefore
	// stayed on screen after an approval and could be pressed again.
	//
	// Pages 1..n must be cached, because `more(page)` pages by absolute offset and
	// nothing else supplies them. They are stamped with the pagination window they
	// were fetched against, since those offsets mean nothing once a row is inserted.
	// Comparing the window — rather than the prop's identity — is what distinguishes a
	// real shift from the `invalidateAll()` that `handle()` runs after every write and
	// that every realtime tick runs: keying on identity threw away every page the
	// scholar had loaded and scrolled them back to the top whenever anything on the
	// page changed at all. A stale stamp can never match again, because `count` is in
	// the key and transactions are never deleted (DESIGN.md, Transactions), so the
	// count only ever rises.
	let windowKey = $derived(`${count}:${transactions.map((t) => t.id).join(',')}`);
	let loaded = $state.raw<{ key: string; pages: TransactionListRow[][] }>({ key: '', pages: [] });
	let morePages = $derived(loaded.key === windowKey ? loaded.pages : []);

	// Newest first, matching the three server queries' `created_at desc, seq desc` (the
	// sort is stable, so rows sharing a timestamp keep the server's `seq` order).
	// Sorted on a copy: `transactions` belongs to the load function's data.
	let allTransactions = $derived(
		[...transactions, ...morePages.flat()].sort(
			(a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
		)
	);

	let loading = $state(false);
	async function loadMore() {
		// Don't load more if we've already loaded all transactions.
		if (allTransactions.length >= count) return;
		loading = true;
		// Read the window before awaiting. If a row arrives while this request is in
		// flight, what comes back is offset against a window that no longer exists;
		// stamping it with the key it was fetched under is what discards it.
		const key = windowKey;
		const previous = morePages;
		const { data, error } = await more(previous.length + 1);
		if (error || data === null)
			addError({ message: locale().view.transactions.feedback.notLoaded, details: error });
		else loaded = { key, pages: [...previous, data] };
		loading = false;
	}

	/** Refetch whichever loaded page holds this transaction. Page 0 is the prop and
	 * `handle()`'s invalidateAll has already refreshed it; pages 1..n are snapshots, so
	 * a row approved down there would keep rendering its old status and its Approve
	 * button. */
	async function refresh(id: TransactionListRow['id']) {
		const index = morePages.findIndex((rows) => rows.some((t) => t.id === id));
		if (index < 0) return;
		const key = windowKey;
		const previous = morePages;
		const { data, error } = await more(index + 1);
		if (error || data === null)
			addError({ message: locale().view.transactions.feedback.notLoaded, details: error });
		else loaded = { key, pages: previous.map((rows, i) => (i === index ? data : rows)) };
	}
</script>

{#snippet row(transaction: TransactionListRow, index: number)}
	{@const currency = currencies?.find((c) => c.id === transaction.currency)}
	{@const proposed = transaction.status === 'proposed'}
	{@const pureMint = transaction.from_scholar === null && transaction.from_venue === null}
	{@const editable =
		proposed &&
		userid !== null &&
		(transaction.from_scholar === userid ||
			(transaction.from_venue !== null &&
				venues.find((v) => v.id === transaction.from_venue)?.admins.includes(userid)) ||
			currency?.minters.includes(userid)) &&
		// Anti-self-dealing: hide approval from recipients. A pure mint is exempt, mirroring
		// approve_transaction: it brings new tokens into existence rather than moving
		// someone else's, so a minter who also administers the venue may approve it. That is
		// the shortfall mint a payout records, and hiding it here would strand the one person
		// a small community has to approve it.
		transaction.to_scholar !== userid &&
		(pureMint ||
			!(
				transaction.to_venue !== null &&
				venues.find((v) => v.id === transaction.to_venue)?.admins.includes(userid)
			))}
	<tr data-testid={testid + '-' + index}>
		<td>
			<Status
				testid={testid + '-' + index + '-status'}
				good={transaction.status === 'approved'}
				label={(l) =>
					transaction.status === 'approved'
						? l.view.transactions.status.approved
						: transaction.status === 'declined'
							? l.view.transactions.status.declined
							: l.view.transactions.status.proposed}
			/>
		</td>
		<td><Tokens amount={transaction.amount} debit={isDebit(transaction)} {currency} /></td>
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
					slug={venues.find((v) => v.id === transaction.from_venue)?.slug ?? null}
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
					slug={venues.find((v) => v.id === transaction.to_venue)?.slug ?? null}
					name={venues.find((v) => v.id === transaction.to_venue)?.title ??
						locale().view.transactions.error.unknownVenue}
				></VenueLink>{/if}</td
		>
		<td>
			<Note path={() => transaction.purpose} />
			{#if transaction.status === 'declined' && transaction.decline_reason !== null}
				<div class="decline">
					<em
						>Declined{#if transaction.decliner}
							by <ScholarLink id={transaction.decliner} />{/if}:</em
					>
					<Note path={() => transaction.decline_reason ?? ''} />
				</div>
			{/if}
		</td>
		<td>
			{#if editable && userid !== null}
				<TransactionActions
					{transaction}
					{index}
					{userid}
					testid={testid ?? ''}
					onChange={refresh}
				/>
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
		{#each allTransactions as transaction, index}
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
