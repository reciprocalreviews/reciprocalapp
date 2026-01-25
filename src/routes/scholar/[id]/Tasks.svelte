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
	import Tip from '$lib/components/Tip.svelte';
	import VenueLink from '$lib/components/VenueLink.svelte';
	import { getDB } from '$lib/data/CRUD';
	import { handle } from '../../feedback.svelte';

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

	const invitedCommitments = $derived(commitments.filter((c) => c.invited));
</script>

<Subheader icon={TaskLabel}>Tasks</Subheader>

{#if invitedCommitments.length === 0 && (pending === null || pending.length === 0) && (reviews === null || reviews.length === 0) && (approvals === null || approvals.length === 0)}
	<Feedback>You have no pending tasks.</Feedback>
{:else}
	<Tip>These are tasks you need to complete.</Tip>

	<Table>
		{#snippet header()}
			<th>Kind</th>
			<th>Task</th>
		{/snippet}
		<!-- Show pending invitations -->
		{#each invitedCommitments as invite}
			<tr>
				<td>Invitation</td>
				<td>
					The editor has invited you to the <strong>{invite.name ?? EmptyLabel}</strong>
					role for <VenueLink id={invite.venueid} name={invite.venue} />. Would you like to
					<Button
						tip="accept this invitation"
						action={() => handle(db().acceptRoleInvite(scholar, invite.id, 'accepted'))}
						>Accept</Button
					>
					<Button
						tip="decline this invitation"
						action={() => handle(db().acceptRoleInvite(scholar, invite.id, 'declined'))}
						>Decline</Button
					>?
				</td>
			</tr>
		{/each}

		<!-- Show pending transactions -->
		{#each minting ?? [] as currency}
			{@const pendingForCurrency = pending?.filter((t) => t.currency === currency.id) ?? []}
			{#if pendingForCurrency.length > 0}
				<tr>
					<td>Transaction</td>
					<td>
						As minter, you have {pendingForCurrency.length} proposed transactions to approve. Approve
						them in the <CurrencyLink {currency} transactions /> dashboard.
					</td>
				</tr>
			{/if}
		{/each}

		<!-- Show pending reviews -->
		{#each reviews ?? [] as review}
			<tr>
				<td>Review</td>
				<td>
					<SubmissionLink submission={review.submissions} />
				</td>
			</tr>
		{/each}

		<!-- Show pending assignments -->
		{#each approvals ?? [] as approval}
			<tr>
				<td>Assignment</td>
				<td>
					<ScholarLink id={approval.scholars} /> pending assignment to <SubmissionLink
						submission={approval.submissions}
					/>
				</td>
			</tr>
		{/each}
	</Table>
{/if}
