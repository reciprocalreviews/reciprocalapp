<script lang="ts">
	import type { CurrencyRow, VenueRow } from '$data/types';
	import { getDB } from '$lib/data/CRUD';
	import type { TransactionListRow } from '$lib/data/SupabaseCRUD.svelte';
	import Text from '$lib/locales/Text.svelte';
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
	const db = getDB();

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

	/** Every row the pages loaded so far hold, in the order the server returned them.
	 * The "load more" stop condition counts these and only these: `count` counts rows
	 * in the table, and a pinned decision (below) is one of them, fetched early. */
	let pageRows = $derived([...transactions, ...morePages.flat()]);

	// Transactions the viewer has approved or declined during this visit, held in the
	// list even after the server stops returning them on a loaded page.
	//
	// Deciding a transaction moves it: proposed rows sort to the front, so approving
	// one drops it into the settled history by date — which on any venue with a year
	// of transactions is several pages down. The row simply vanished from under the
	// pointer, leaving no evidence of what the decision did, and the reason a decline
	// records was never seen at all. Pinning the refetched row keeps it where it was
	// acted on, showing its new status, until the next navigation clears this.
	let decided = $state.raw<TransactionListRow[]>([]);
	let decidedIDs = $derived(new Set(decided.map((t) => t.id)));
	let pinnedRows = $derived(decided.filter((d) => !pageRows.some((t) => t.id === d.id)));

	// Proposed first, then newest, matching the three server queries' `status asc,
	// created_at desc, seq desc`. This must mirror the server order, not merely be a
	// defensible order of its own: the pages it merges were cut by the server, so any
	// other ordering shuffles rows across the boundaries between them.
	//
	// Proposed first is what keeps an old unapproved transaction reachable at all. It is
	// a minority status on a table that only grows, and paging by date alone buried the
	// work an approver still owes behind however many pages of settled history had
	// accumulated since — with nothing on screen to say it was down there.
	//
	// A row the viewer just decided sorts with the proposed ones rather than by its new
	// status, which is what holds it still; everything else about it is the server's
	// current copy.
	//
	// The sort is stable, so rows sharing a timestamp keep the server's `seq` order.
	// Sorted on a copy: `transactions` belongs to the load function's data.
	let allTransactions = $derived(
		[...pageRows, ...pinnedRows].sort((a, b) => {
			const pending = Number(pendingBlock(b)) - Number(pendingBlock(a));
			if (pending !== 0) return pending;
			return new Date(b.created_at).getTime() - new Date(a.created_at).getTime();
		})
	);

	function pendingBlock(transaction: TransactionListRow): boolean {
		return transaction.status === 'proposed' || decidedIDs.has(transaction.id);
	}

	/** The day, in the reader's locale, with the full timestamp on hover. A transaction
	 * list spans years, so the day is what distinguishes rows; the time only matters when
	 * two rows share a day, and that is what the tooltip is for. */
	function formatDate(iso: string): string {
		return new Date(iso).toLocaleDateString();
	}

	let loading = $state(false);
	async function loadMore() {
		// Don't load more if we've already loaded all transactions.
		if (pageRows.length >= count) return;
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

	/** Take up a transaction the viewer has just decided.
	 *
	 * Two things have to happen, and neither covers the other. The row is pinned, so
	 * that a decision which moved it out of the loaded pages still shows its outcome
	 * where it was made — that needs the row refetched on its own, since the lists no
	 * longer return it. And whichever cached page held it is refetched, because pages
	 * 1..n are snapshots: a row approved down there would otherwise keep rendering its
	 * old status and its Approve button. (Page 0 is the prop, which `handle()`'s
	 * invalidateAll has already refreshed by the time this runs.) */
	async function refresh(id: TransactionListRow['id']) {
		const { data: row, error: rowError } = await db().getTransaction(id);
		if (rowError || row === null)
			addError({
				message: locale().view.transactions.feedback.notLoaded,
				details: rowError ?? undefined
			});
		else decided = [...decided.filter((t) => t.id !== id), row];

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
		<td title={new Date(transaction.created_at).toLocaleString()}
			>{formatDate(transaction.created_at)}</td
		>
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
					<!-- `{' '}` rather than a line break: Svelte trims the whitespace at the start
					     of a block, so the newline after `{#if}` rendered "Declinedby Name". -->
					<em
						>Declined{#if transaction.decliner}{' '}by <ScholarLink
								id={transaction.decliner}
							/>{/if}:</em
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
	<Note path={(l) => l.view.transactions.note.sortOrder} />
	<Table full>
		{#snippet header()}
			<!-- The two columns the list is ordered by, in the order it is ordered by them,
			     so the arrangement can be read off the table rather than inferred. -->
			<th aria-sort="ascending">{locale().view.transactions.headers.status}</th>
			<th aria-sort="descending">{locale().view.transactions.headers.date}</th>
			<th>{locale().view.transactions.headers.tokens}</th>
			<th>{locale().view.transactions.headers.scholar}</th>
			<th>{locale().view.transactions.headers.from}</th>
			<th>{locale().view.transactions.headers.to}</th>
			<th>{locale().view.transactions.headers.purpose}</th>
			<th>{locale().view.transactions.headers.actions}</th>
		{/snippet}
		<!-- Keyed by id. Unkeyed, Svelte matches rows to components by POSITION, so a list
		     that reorders — which it now does the moment a transaction is approved or
		     declined — hands a row's component the next row's data while keeping its state:
		     the open decline dialog, and the `transaction` that the button's own handler
		     reads after its await. A decision was then reported back against whichever
		     transaction had slid into that slot. -->
		{#each allTransactions as transaction, index (transaction.id)}
			{@render row(transaction, index)}
		{/each}
		<tr>
			<td colspan="100">
				{#if pageRows.length >= count}
					{locale().view.transactions.cell.allLoaded}
				{:else}
					<!-- The label is rendered here rather than left to Button: passing ANY
					     children suppresses Button's own `strings().label`, so a snippet that
					     was empty unless loading left a blank square on screen whose only text
					     was its tooltip. -->
					<Button
						strings={(l) => l.view.transactions.button.loadMore}
						action={() => loadMore()}
						active={!loading}
						><Text
							path={(l) => l.view.transactions.button.loadMore.label}
						/>{#if loading}…{/if}</Button
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
