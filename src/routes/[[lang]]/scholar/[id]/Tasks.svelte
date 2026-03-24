<script lang="ts">
	import type {
		AssignmentRow,
		CurrencyRow,
		ScholarID,
		ScholarRow,
		SubmissionRow,
		TransactionRow
	} from '$data/types';
	import Button from '$lib/components/Button.svelte';
	import CurrencyLink from '$lib/components/CurrencyLink.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import { EmptyLabel, TaskLabel } from '$lib/components/Labels';
	import ScholarLink from '$lib/components/ScholarLink.svelte';
	import Subheader from '$lib/components/Subheader.svelte';
	import SubmissionLink from '$lib/components/SubmissionLink.svelte';
	import Table from '$lib/components/Table.svelte';
	import Text from '$lib/locales/Text.svelte';
	import Tip from '$lib/components/Tip.svelte';
	import VenueLink from '$lib/components/VenueLink.svelte';
	import { getDB } from '$lib/data/CRUD';
	import { handle } from '$routes/feedback.svelte';
	import { getLocaleContext } from '$routes/Contexts';

	let {
		commitments,
		pending,
		minting,
		scholar,
		reviews,
		approvals
	}: {
		commitments: { id: string; invited: boolean; name: string; venue: string; venueid: string }[];
		minting: CurrencyRow[] | null;
		pending: TransactionRow[] | null;
		scholar: ScholarID;
		reviews: (AssignmentRow & { submissions: SubmissionRow })[] | null;
		approvals: (AssignmentRow & { scholars: ScholarRow; submissions: SubmissionRow })[] | null;
	} = $props();

	const db = getDB();
	const locale = getLocaleContext();

	const invitedCommitments = $derived(commitments.filter((c) => c.invited));
</script>

<Subheader icon={TaskLabel} text={(l) => l.page.scholar.header.tasks}></Subheader>

{#if invitedCommitments.length === 0 && (pending === null || pending.length === 0) && (reviews === null || reviews.length === 0) && (approvals === null || approvals.length === 0)}
	<Feedback text={(l) => l.page.scholar.feedback.noTasks}></Feedback>
{:else}
	<Tip><Text path={(l) => l.view.tasks.tip.tasks} /></Tip>

	<Table>
		{#snippet header()}
			<th>{locale.view.tasks.headers.kind}</th>
			<th>{locale.view.tasks.headers.task}</th>
		{/snippet}
		<!-- Show pending invitations -->
		{#each invitedCommitments as invite, index}
			<tr data-testid="invitation-{index}">
				<td>{locale.view.tasks.cell.kind.invitation}</td>
				<td>
					<strong>{invite.name ?? EmptyLabel}</strong>
					<VenueLink id={invite.venueid} name={invite.venue} />
					<Button
						strings={(l) => l.view.tasks.button.accept}
						action={() => handle(db().acceptRoleInvite(scholar, invite.id, 'accepted'))}
					/>
					<Button
						strings={(l) => l.view.tasks.button.decline}
						action={() => handle(db().acceptRoleInvite(scholar, invite.id, 'declined'))}
					/>?
				</td>
			</tr>
		{/each}

		<!-- Show pending transactions -->
		{#each minting ?? [] as currency, index}
			{@const pendingForCurrency = pending?.filter((t) => t.currency === currency.id) ?? []}
			{#if pendingForCurrency.length > 0}
				<tr data-testid="transaction-{index}">
					<td>{locale.view.tasks.cell.kind.transaction}</td>
					<td>
						{pendingForCurrency.length}
						<CurrencyLink {currency} transactions /> {locale.view.tasks.cell.pendingTransactionsAfter}
					</td>
				</tr>
			{/if}
		{/each}

		<!-- Show pending reviews -->
		{#each reviews ?? [] as review, index}
			<tr data-testid="review-{index}">
				<td>{locale.view.tasks.cell.kind.review}</td>
				<td>
					<SubmissionLink submission={review.submissions} />
				</td>
			</tr>
		{/each}

		<!-- Show pending assignments -->
		{#each approvals ?? [] as approval, index}
			<tr data-testid="assignment-{index}">
				<td>{locale.view.tasks.cell.kind.pendingAssignment}</td>
				<td>
					<ScholarLink id={approval.scholars} />
					<SubmissionLink submission={approval.submissions} />
				</td>
			</tr>
		{/each}
	</Table>
{/if}
