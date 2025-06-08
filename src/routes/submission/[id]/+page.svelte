<script lang="ts">
	import Feedback from '$lib/components/Feedback.svelte';
	import { type PageData } from './$types';
	import Page from '$lib/components/Page.svelte';
	import VenueLink from '$lib/components/VenueLink.svelte';
	import ScholarLink from '$lib/components/ScholarLink.svelte';
	import Tokens from '$lib/components/Tokens.svelte';
	import Row from '$lib/components/Row.svelte';
	import EditableText from '$lib/components/EditableText.svelte';
	import { getDB } from '$lib/data/CRUD';
	import Link from '$lib/components/Link.svelte';
	import Status from '$lib/components/Status.svelte';
	import Checkbox from '$lib/components/Checkbox.svelte';
	import Tag from '$lib/components/Tag.svelte';
	import Table from '$lib/components/Table.svelte';
	import Button from '$lib/components/Button.svelte';
	import { handle } from '../../feedback.svelte';
	import { EmptyLabel } from '$lib/components/Labels';
	import type { RoleID, ScholarID } from '$data/types';
	import isRoleApprover from '$lib/data/isRoleApprover';

	let { data }: { data: PageData } = $props();
	const {
		/** The submission being viewed */
		submission,
		/** The venue of the submission being viewed */
		venue,
		/** The authors of the submission viewing viewed */
		authors,
		/** The previous submission, if there is one */
		previous,
		/** Transactions related to the submission, if visible */
		transactions,
		/** The roles for this venue */
		roles,
		/** All volunteers for this venue */
		volunteers,
		/** All assignments related to this submission */
		assignments,
		/** All balances of scholars */
		balances,
		/** The current user */
		user
	} = $derived(data);

	/** Get the database connection */
	const db = getDB();

	/** Whether the current scholar is an editor */
	let isEditor = $derived(venue !== null && user !== null && venue.editors.includes(user.id));

	/** The transactions corresponding to each of the authors */
	const authorTransactions = $derived(
		submission === null || transactions === null
			? null
			: submission.transactions.map((id) => transactions.find((t) => t.id === id))
	);

	/** Whether this submission is no longer in review */
	const done = $derived(submission?.status === 'done');

	/** Whether the current scholar is an author of the submission */
	let isAuthor = $derived(
		submission !== null && user !== null && submission.authors.includes(user.id)
	);

	/** Whether the current scholar is assigned to this submission */
	let isAssigned = $derived(
		user !== null && assignments?.find((a) => a.scholar === user.id && a.approved) !== undefined
	);

	function getVolunteer(role: RoleID, scholar: ScholarID) {
		return volunteers?.find((v) => v.roleid === role && v.scholarid === scholar);
	}

	function getBalance(scholar: ScholarID) {
		return balances?.find((balance) => balance.scholar === scholar)?.count ?? 0;
	}
</script>

{#if submission === null || venue === null || roles === null || user === null || assignments === null || authors === null || volunteers === null}
	<Page
		title="Submission"
		breadcrumbs={[
			[`/venue/${venue?.id}`, venue?.title ?? ''],
			[`/venue/${venue?.id}/submissions`, 'Submissions']
		]}
	>
		<Feedback error>This submission does not exist or is not visible to you.</Feedback>
	</Page>
{:else if !isEditor && !isAuthor && !isAssigned}
	<Page
		title="Submission"
		breadcrumbs={[
			[`/venue/${venue?.id}`, venue?.title ?? ''],
			[`/venue/${venue?.id}/submissions`, 'Submissions']
		]}
	>
		<Feedback error>You this submission is confidential.</Feedback>
	</Page>
{:else}
	<Page
		title={submission.title}
		breadcrumbs={[
			[`/venue/${submission.venue}`, venue?.title ?? ''],
			[`/venue/${submission.venue}/submissions`, 'Submissions']
		]}
		edit={// Only editors can update the submission title.
		isEditor
			? {
					placeholder: 'Title',
					valid: (text) => (text.trim().length === 0 ? 'Title cannot be empty.' : undefined),
					update: (text) => db.updateSubmissionTitle(submission.id, text)
				}
			: undefined}
	>
		{#snippet subtitle()}Submission{/snippet}
		{#snippet details()}
			{#if previous}<Link to="/submission/{previous.id}">{previous.externalid}</Link>
				→{/if}
			{submission.externalid}
			{#if done}<Status good={false}>done</Status>{:else}<Status>reviewing</Status>{/if}
		{/snippet}

		<!-- Only editors can update the status of a submission -->
		{#if isEditor}
			<Checkbox
				on={!done}
				change={(on) => db.updateSubmissionStatus(submission.id, on ? 'reviewing' : 'done')}
				>This submission is still in review.</Checkbox
			>
		{/if}

		<h2>Authors</h2>

		{#each submission.authors as author}
			{@const authorIndex = authors.findIndex((a) => a.id === author)}
			{@const payment = authorIndex !== undefined ? submission.payments[authorIndex] : undefined}
			{@const transaction =
				authorTransactions === null || authorIndex === undefined
					? undefined
					: authorTransactions[authorIndex]}
			<Row>
				{#if authorIndex === undefined}
					<Feedback error>Unable to find authors.</Feedback>
				{:else if isEditor || isAuthor}
					<ScholarLink id={author}></ScholarLink>
					{#if payment !== undefined}
						{#if transaction === undefined}
							<Status good={false}>unknown transaction</Status>
						{:else}
							{#if transaction.status === 'proposed'}
								proposes to pay
							{:else if transaction.status === 'approved'}
								paid
							{:else if transaction.status === 'canceled'}
								declined to pay
							{/if}
							<Tokens amount={payment} />
						{/if}
					{/if}
				{:else}
					<em>anonymized</em>
				{/if}
			</Row>
		{:else}
			<Feedback error>No visible authors found.</Feedback>
		{/each}

		<h2>Venue</h2>
		<VenueLink id={venue.id} name={venue.title} />

		<h2>Expertise</h2>
		{#if isAuthor}
			<EditableText
				text={submission.expertise ?? ''}
				placeholder="Expertise"
				edit={(text) =>
					db.updateSubmissionExpertise(submission.id, text.trim().length === 0 ? null : text)}
			/>
		{:else if submission.expertise}
			{submission.expertise}
		{:else}
			<Feedback>No expertise provided</Feedback>
		{/if}

		<h2>Assignments</h2>

		<Table full>
			{#snippet header()}
				<th>Role</th><th>Scholar</th><th>Expertise</th><th>Balance</th><th>Action</th>
			{/snippet}

			<!-- First, show the editors -->
			{#each venue.editors as editor}
				<tr>
					<td>Editor</td>
					<td><ScholarLink id={editor}></ScholarLink></td>
					<td>{EmptyLabel}</td>
					<td>{EmptyLabel}</td>
					<td>{EmptyLabel}</td>
				</tr>
			{/each}

			<!-- Sort roles by priority -->
			{#each roles.toSorted((a, b) => a.priority - b.priority) as role}
				{@const assigned = assignments.filter((a) => role.id === a.role && a.approved)}
				<!-- The bidding assignments are those that match this role and aren't approved. We sort them by the balances of the corresponding scholar. -->
				{@const bidded = assignments
					.filter((a) => role.id === a.role && a.bid && !a.approved)
					.toSorted((a, b) => getBalance(a.scholar) - getBalance(b.scholar))}
				{@const isApprover =
					isEditor || (user !== null && isRoleApprover(role, volunteers, user.id))}
				{#each assigned as assignment}
					{@const volunteer = getVolunteer(role.id, assignment.scholar)}
					<tr>
						<td>{role.name}</td>
						<td><ScholarLink id={assignment.scholar} /> <Tag>Assigned</Tag></td>
						<td
							>{#if volunteer}{volunteer.expertise}{:else}{EmptyLabel}{/if}</td
						>
						<td>{getBalance(assignment.scholar)}</td>
						<td>
							<Row>
								{#if isApprover}
									<Button
										tip="Remove this assignment"
										action={() => handle(db.approveAssignment(assignment, false, role, user.id))}
										>Unassign</Button
									>
								{:else}
									{EmptyLabel}
								{/if}
							</Row>
						</td>
					</tr>
				{:else}
					{#if bidded.length === 0}
						<tr><td>{role.name}</td><td colspan="4">{EmptyLabel}</td></tr>
					{/if}
				{/each}

				<!-- Is the current scholar an approver of this role? The bids so they can be approved. -->
				{#if bidded.length > 0 && isApprover}
					{#each bidded as assignment}
						{@const volunteer = getVolunteer(role.id, assignment.scholar)}
						<tr>
							<td>{role.name}</td>
							<td><ScholarLink id={assignment.scholar} /></td>
							<td
								>{#if volunteer}{volunteer.expertise}{:else}{EmptyLabel}{/if}</td
							>
							<td>{getBalance(assignment.scholar)}</td>
							<td>
								<Row>
									{#if assignment.bid}
										<Button
											tip="Accept this bid, assigning this scholar to this role for this submission."
											action={() =>
												user ? handle(db.approveAssignment(assignment, true, role, user.id)) : null}
											>Assign</Button
										>
									{/if}
								</Row>
							</td>
						</tr>
					{/each}
				{/if}
			{/each}
		</Table>
	</Page>
{/if}
