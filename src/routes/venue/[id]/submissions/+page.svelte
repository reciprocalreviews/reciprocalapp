<script lang="ts">
	import Feedback from '$lib/components/Feedback.svelte';
	import SubmissionPreview from '$lib/components/SubmissionLink.svelte';
	import Table from '$lib/components/Table.svelte';
	import { getAuth } from '../../../Auth.svelte';
	import { type PageData } from './$types';
	import Page from '$lib/components/Page.svelte';
	import Link from '$lib/components/Link.svelte';
	import Cards from '$lib/components/Cards.svelte';
	import Card from '$lib/components/Card.svelte';
	import NewSubmission from './NewSubmission.svelte';
	import { getDB, NullUUID } from '$lib/data/CRUD';
	import Button from '$lib/components/Button.svelte';
	import ScholarLink from '$lib/components/ScholarLink.svelte';
	import { handle } from '../../../feedback.svelte';
	import Status from '$lib/components/Status.svelte';
	import Column from '$lib/components/Column.svelte';

	let { data }: { data: PageData } = $props();
	const { venue, submissions, volunteering, roles, assignments, transactions } = $derived(data);

	const db = getDB();
	const auth = getAuth();

	const uid = $derived(auth.getUserID());
	const editor = $derived(uid !== null && venue !== null && venue.editors.includes(uid));

	// Show the bidding interface if there's a venue, its biddable
	const submissionCost = $derived(venue?.submission_cost ?? null);

	const sortedRoles = $derived(roles?.toSorted((a, b) => a.priority - b.priority));

	let newSubmissionExpanded = $state(false);
</script>

{#if venue}
	<Page
		title="Submissions"
		breadcrumbs={[
			['/venues', 'Venues'],
			[`/venue/${venue.id}`, venue.title]
		]}
	>
		{#snippet details()}<Link to={venue.url}>{venue.url}</Link>{/snippet}

		<Cards>
			{#if editor && submissionCost !== null}
				<Card
					icon="+"
					header="New submission"
					note="Manually create a new submission"
					group="editors"
					bind:expand={newSubmissionExpanded}
				>
					<NewSubmission bind:expanded={newSubmissionExpanded} venue={venue.id} {submissionCost}
					></NewSubmission>
				</Card>
			{/if}
		</Cards>

		{#if submissions}
			{#if submissions.length === 0}
				<Feedback>No submissions, or none visible to you.</Feedback>
			{:else}
				<Table full>
					{#snippet header()}
						<th>Payment</th>
						<th>Submission</th>
						<th>Expertise</th>
						<th>External ID</th>
						<!-- If bidding is enabled, add column for each of the scholar's volunteer roles -->
						{#if volunteering && sortedRoles && assignments}
							{#if editor}
								{#each sortedRoles as role}
									<th>{role.name}</th>
								{/each}
							{:else}
								{#each volunteering as commitment}
									<th>{sortedRoles?.find((role) => role.id === commitment.roleid)?.name ?? '—'}</th>
								{/each}
							{/if}
						{/if}
					{/snippet}
					{#each submissions as submission}
						{@const submissionTransactions =
							transactions === null
								? null
								: submission.transactions
										.filter((t) => t === NullUUID)
										.map((t) => transactions.find((tr) => tr.id === t))
										.filter((t) => t !== undefined)}
						<tr>
							<td>
								<!-- Couldn't load transactions? -->
								{#if submissionTransactions === null}
									—
								{:else if submissionTransactions.length === submission.transactions.length}
									<Status>paid</Status>
								{:else}
									<Status good={false}>
										{submission.transactions.length - submissionTransactions.length} pending</Status
									>
								{/if}
							</td>
							<td><SubmissionPreview {submission} /></td>
							<td>{submission.expertise}</td>
							<td>{submission.externalid}</td>
							<!-- If we have all the information, show metadata about bidding. -->
							{#if volunteering && sortedRoles && assignments && uid}
								{#each sortedRoles as role}
									{@const submissionAssignments = assignments.filter(
										(ass) => ass.submission === submission.id && ass.role === role.id
									)}
									{@const assigned = submissionAssignments.filter((a) => a.approved)}
									{@const bid = submissionAssignments.find((a) => a.scholar === uid && a.bid)}
									<td>
										<Column>
											{#if editor}
												{#each assigned as assignment}
													<!-- Editor? Show the people assigned. Otherwise, show bidding interface. -->
													<ScholarLink id={assignment.scholar} />
												{/each}
												<span>{submissionAssignments.filter((a) => a.bid).length} bids</span>
											{/if}

											<!-- Active assignment? -->
											{#if role.biddable}
												{#if bid === undefined || !bid.approved}
													<!-- No assignments? Allow bidding -->
													<Button
														tip="Express interest in serving as {role?.description ??
															'in this role'}"
														action={() =>
															handle(db.createAssignment(submission.id, uid, role.id, true))}
														>Bid</Button
													>
												{:else if bid !== undefined && !bid.approved}
													<Button
														tip="Remove interest in serving as {role?.description ??
															'in this role'}"
														action={() => handle(db.deleteAssignment(bid.id))}>Unbid</Button
													>
												{/if}
											{/if}
										</Column>
									</td>
								{/each}
							{/if}
						</tr>
					{:else}
						<Feedback>No active submissions.</Feedback>
					{/each}
				</Table>
			{/if}
		{:else}
			<Feedback error>Unable to load submissions.</Feedback>
		{/if}
	</Page>
{/if}
