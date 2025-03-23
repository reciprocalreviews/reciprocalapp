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
	import { CreateLabel, PrivateLabel } from '$lib/components/Labels';
	import Column from '$lib/components/Row.svelte';

	let { data }: { data: PageData } = $props();
	const {
		/** The venue of this route */
		venue,
		/** All submissions for this venue */
		submissions,
		/** All volunteers for this venue (if an editor) and all accepted, active volunteers for everyone else */
		volunteering,
		/** All roles in this venue */
		roles,
		/** If an editor, all submission assignments; otherwise, all of the current scholar's assignments. */
		assignments,
		/** All transctions for all submissions in this venue */
		transactions
	} = $derived(data);

	/** Get the current database connection */
	const db = getDB();

	/** Get the current auth state */
	const auth = getAuth();

	/** Get the current user ID state */
	const uid = $derived(auth.getUserID());

	/** True if the current user is an editor of this venue */
	const isEditor = $derived(uid !== null && venue !== null && venue.editors.includes(uid));

	/** The cost of submissions, if there is one. */
	const submissionCost = $derived(venue?.submission_cost ?? null);

	/** The roles to show, filtered by the which role the current scholar has */
	const visibleRoles = $derived(
		roles === null || volunteering === null
			? []
			: roles
					.toSorted((a, b) => a.priority - b.priority)
					.map((role) => {
						const hasRole = volunteering.some(
							(v) => v.scholarid === uid && v.roleid === role.id && v.accepted === 'accepted'
						);
						const isApprover =
							isEditor ||
							volunteering.some(
								(v) =>
									v.accepted === 'accepted' && v.scholarid === uid && role.approver === v.roleid
							);

						return {
							...role,
							isVisible: isEditor || role.biddable || hasRole || isApprover,
							hasRole,
							isApprover
						};
					})
					.filter((r) => r.isVisible)
	);

	/** Whether the new submission card is expanded */
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

		<!-- If an editor and there's a submission cost, show the new submission form -->
		{#if isEditor && submissionCost !== null}
			<Cards>
				<Card
					icon={CreateLabel}
					header="New submission"
					note="Manually create a new submission"
					group="editors"
					bind:expand={newSubmissionExpanded}
				>
					<NewSubmission bind:expanded={newSubmissionExpanded} venue={venue.id} {submissionCost}
					></NewSubmission>
				</Card>
			</Cards>
		{/if}

		{#if submissions}
			{#if submissions.length === 0}
				<Feedback>This venue has no submissions (or none visible to you).</Feedback>
			{:else}
				<!-- Show a full-width table of all submissions, metadata about each, and bidding buttons if the current scholar is a volunteer. -->
				<Table full>
					{#snippet header()}
						<th>Payment</th>
						<th>Submission</th>
						<th>Expertise</th>
						<th>ID</th>
						<!-- If bidding is enabled, add column for each of the scholar's volunteer roles -->
						{#each visibleRoles as role}
							<th>{role.name}</th>
						{/each}
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
									{PrivateLabel}
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
							{#each visibleRoles as role}
								<!-- This cell should show all actions available for this role and submission, based on the current scholar's role. -->
								<td>
									<Column>
										{#if uid}
											{@const roleAssignments = assignments?.filter(
												(a) => a.submission === submission.id && a.role === role.id
											)}
											{@const approvedAssignments =
												roleAssignments?.filter((a) => a.approved) ?? []}
											{@const bids = roleAssignments?.filter((a) => a.bid) ?? []}
											{@const scholarsBid = bids?.find((a) => a.scholar === uid)}
											<!-- If the current scholar is an approver, show the current assignemnts -->
											{#if role.isApprover}
												{#each approvedAssignments as assignment}
													<!-- Editor? Show the people assigned. Otherwise, show bidding interface. -->
													<ScholarLink id={assignment.scholar} />
												{:else}
													<span><strong>0</strong> assigned</span>
												{/each}
											{/if}

											<!-- Show bidding if the role is biddable, as bidding is public. -->
											{#if role.biddable}
												<!-- If the current scholar is an editor or approver for this role, show the number of bids. -->
												{#if role.isApprover}
													<div><strong>{bids.length}</strong> bids</div>
												{:else if scholarsBid === undefined}
													<!-- No assignments? Allow bidding -->
													<Button
														tip="Express interest in serving as {role?.description ??
															'in this role'}"
														action={() =>
															handle(db.createAssignment(submission.id, uid, role.id, true))}
														>Bid</Button
													>
												{:else if scholarsBid !== undefined && !scholarsBid.approved}
													<!-- Shown an unbid button if not yet approved -->
													<Button
														tip="Remove interest in serving as {role?.description ??
															'in this role'}"
														action={() => handle(db.deleteAssignment(scholarsBid.id))}>Unbid</Button
													>
												{/if}
											{/if}
										{:else}
											<!-- Not logged in? Don't show any information. -->
											{PrivateLabel}
										{/if}
									</Column>
								</td>
							{/each}
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
