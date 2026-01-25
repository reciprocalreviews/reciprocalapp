<script lang="ts">
	import Feedback from '$lib/components/Feedback.svelte';
	import SubmissionPreview from '$lib/components/SubmissionLink.svelte';
	import Table from '$lib/components/Table.svelte';
	import { getAuth } from '../../../Auth.svelte';
	import { type PageData } from './$types';
	import Page from '$lib/components/Page.svelte';
	import Link from '$lib/components/Link.svelte';
	import { getDB, NullUUID } from '$lib/data/CRUD';
	import Button from '$lib/components/Button.svelte';
	import ScholarLink from '$lib/components/ScholarLink.svelte';
	import { handle } from '../../../feedback.svelte';
	import Status from '$lib/components/Status.svelte';
	import { DownLabel, FilterLabel, PrivateLabel, UpLabel } from '$lib/components/Labels';
	import Column from '$lib/components/Row.svelte';
	import isRoleApprover from '$lib/data/isRoleApprover';
	import type { SubmissionRow } from '$data/types';
	import TextField from '$lib/components/TextField.svelte';

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
		transactions,
		/** The conflicts for the current scholar */
		conflicts
	} = $derived(data);

	/** Get the current database connection */
	const db = getDB();

	/** Get the current auth state */
	const auth = getAuth();

	/** Get the current user ID state */
	const uid = $derived(auth.getUserID());

	/** True if the current user is an editor of this venue */
	const isEditor = $derived(uid !== null && venue !== null && venue.editors.includes(uid));

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
							uid !== null && (isEditor || isRoleApprover(role, volunteering, uid));

						return {
							...role,
							isVisible: isEditor || role.biddable || hasRole || isApprover,
							hasRole,
							isApprover
						};
					})
					.filter((r) => r.isVisible)
	);

	/** State of sorting and filtering */
	let paymentSortPendingFirst = $state(true);
	let titleSortIncreasing = $state(true);
	let idSortIncreasing = $state(true);
	let sortOrder = $state<('payment' | 'title' | 'id')[]>(['title', 'id', 'payment']);
	let filter = $state('');

	/** Sort and filter submissions based on the configuration */
	function sortedAndFiltered(submissions: SubmissionRow[]): SubmissionRow[] {
		const trimmedFilter = filter.trim().toLowerCase();
		const subs = submissions
			.filter(
				(sub) =>
					sub.title.toLowerCase().includes(trimmedFilter) ||
					sub.externalid.toLowerCase().includes(trimmedFilter)
			)
			.filter((sub) => conflicts !== null && !conflicts.some((c) => c.submissionid === sub.id));

		for (const column of sortOrder) {
			switch (column) {
				case 'payment':
					subs.sort(
						(a, b) => (getSubmissionPaymentStatus(a) ?? -1) - (getSubmissionPaymentStatus(b) ?? -1)
					);
					if (!paymentSortPendingFirst) subs.reverse();
					break;
				case 'title':
					subs.sort((a, b) => a.title.localeCompare(b.title));
					if (!titleSortIncreasing) subs.reverse();
					break;
				case 'id':
					subs.sort((a, b) => a.externalid.localeCompare(b.externalid));
					if (!idSortIncreasing) subs.reverse();
					break;
			}
		}
		return subs;
	}

	function getSubmissionPaymentStatus(submission: SubmissionRow): number | undefined {
		const submissionTransactions =
			transactions === null
				? null
				: submission.transactions
						.filter((t) => t !== NullUUID)
						.map((t) => transactions.find((tr) => tr.id === t))
						.filter((t) => t !== undefined);
		if (submissionTransactions === null) return undefined;
		else return submission.transactions.length - submissionTransactions.length;
	}
</script>

{#if venue && conflicts}
	<Page
		title="Submissions"
		breadcrumbs={[
			['/venues', 'Venues'],
			[`/venue/${venue.id}`, venue.title]
		]}
	>
		{#snippet details()}<Link to={venue.url}>{venue.url}</Link>{/snippet}

		<!-- Provide a clear link to the new submission page. -->
		<p>
			Have a submission to pay for? Pay for a <Link to={`submissions/new`}>new submission</Link>.
		</p>

		<TextField label="Filter {FilterLabel}" placeholder="title, id" bind:text={filter}></TextField>

		{#if submissions}
			{#if submissions.length === 0}
				<Feedback>This venue has no submissions (or none visible to you).</Feedback>
			{:else}
				{@const sorted = sortedAndFiltered(submissions)}
				{#if sorted.length === 0}
					<Feedback>All submissions filtered.</Feedback>
				{:else}
					<!-- Show a full-width table of all submissions, metadata about each, and bidding buttons if the current scholar is a volunteer. -->
					<Table full>
						{#snippet header()}
							<th
								>Payment <Button
									small
									background={false}
									tip={paymentSortPendingFirst ? 'Sort by pending last' : 'Sort by pending first'}
									action={() => {
										paymentSortPendingFirst = !paymentSortPendingFirst;
										sortOrder = [...sortOrder.filter((o) => o !== 'payment'), 'payment'];
									}}>{paymentSortPendingFirst ? DownLabel : UpLabel}</Button
								></th
							>
							<th
								>Title <Button
									small
									background={false}
									tip={titleSortIncreasing ? 'Reverse sort by title' : 'Sort by title'}
									action={() => {
										titleSortIncreasing = !titleSortIncreasing;
										sortOrder = [...sortOrder.filter((o) => o !== 'title'), 'title'];
									}}>{titleSortIncreasing ? DownLabel : UpLabel}</Button
								></th
							>
							<th>Expertise</th>
							<th
								>ID <Button
									small
									background={false}
									tip={idSortIncreasing ? 'Reverse sort by ID' : 'Sort by ID'}
									action={() => {
										idSortIncreasing = !idSortIncreasing;
										sortOrder = [...sortOrder.filter((o) => o !== 'id'), 'id'];
									}}>{idSortIncreasing ? DownLabel : UpLabel}</Button
								></th
							>
							<!-- If bidding is enabled, add column for each of the scholar's volunteer roles -->
							{#each visibleRoles as role}
								<th>{role.name}</th>
							{/each}
						{/snippet}
						{#each sorted as submission}
							{@const status = getSubmissionPaymentStatus(submission)}
							<tr>
								<td>
									<!-- Couldn't load transactions? -->
									{#if status === undefined}
										{PrivateLabel}
									{:else if status === 0}
										<Status>paid</Status>
									{:else}
										<Status good={false}>
											{status} pending</Status
										>
									{/if}
								</td>
								<td>
									<Column>
										<SubmissionPreview {submission} />
										{#if uid && conflicts !== null && !conflicts.some((c) => c.scholarid === uid && c.submissionid === submission.id) && assignments !== null && !assignments.some((a) => a.submission === submission.id && a.scholar === uid)}
											<Button
												tip="Declare a conflict with this submission. You will no longer see this submission in your bidding list."
												action={() =>
													handle(db().declareConflict(uid, submission.id, 'Scholar declared'))}
											>
												Declare conflict
											</Button>
										{/if}
									</Column>
								</td>
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
													<!-- Approver? Show the people assigned. -->
													{#each approvedAssignments as assignment}
														{#if assignment.scholar === uid}you{:else}<ScholarLink
																id={assignment.scholar}
															/>{/if}
													{:else}
														<span><strong>0</strong> assigned</span>
													{/each}
												{/if}

												<!-- Show bidding if the role is biddable and there are fewer than the number of desired assignments-->
												{#if role.biddable}
													{#if submission.authors.includes(uid) || conflicts.some((c) => c.scholarid === uid && c.submissionid === submission.id)}
														<!-- Can't bid if conflicted -->
														<div><strong>conflicted</strong></div>
													{:else if roleAssignments === undefined || roleAssignments.length < role.desired_assignments}
														<!-- If the current scholar is an editor or approver for this role, show the number of bids. -->
														{#if role.isApprover}
															<div><strong>{bids.length}</strong> bids</div>
														{/if}
														{#if scholarsBid === undefined}
															<!-- No assignments? Allow bidding -->
															<Button
																tip="Express interest in serving as {role?.description ??
																	'in this role'}"
																action={() =>
																	handle(db().createAssignment(submission.id, uid, role.id, true))}
																>Bid</Button
															>
														{:else if scholarsBid !== undefined && !scholarsBid.approved}
															<!-- Shown an unbid button if not yet approved -->
															<Button
																tip="Remove interest in serving as {role?.description ??
																	'in this role'}"
																action={() => handle(db().deleteAssignment(scholarsBid.id))}
																>Unbid</Button
															>
														{/if}
													{:else}
														<div><strong>bidding closed</strong></div>
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
						{/each}
					</Table>
				{/if}
			{/if}
		{:else}
			<Feedback error>Unable to load submissions.</Feedback>
		{/if}
	</Page>
{/if}
