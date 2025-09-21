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
	import Scholar from '$lib/data/Scholar.svelte';
	import Form from '$lib/components/Form.svelte';
	import Tip from '$lib/components/Tip.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import { validEmail, validORCID } from '$lib/validation';

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
		/** The roles for this submission */
		roles,
		/** All volunteers for this submission */
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

	/** State for the assignment form */
	let newAssignmentRole = $state<RoleID | undefined>(undefined);
	let newAssignmentScholar = $state<string>('');
	let newAssignmentSubmitting = $state(false);
	let newAssignmentError: string | undefined = $state(undefined);

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
			{@const payment = authorIndex > -1 ? submission.payments[authorIndex] : undefined}
			{@const transaction =
				authorTransactions === null || authorIndex === undefined
					? undefined
					: authorTransactions[authorIndex]}
			{@const scholar = authorIndex > -1 ? new Scholar(authors[authorIndex]) : undefined}
			<Row>
				{#if authorIndex === undefined}
					<Feedback error>Unable to find authors.</Feedback>
				{:else if isEditor || isAuthor}
					<ScholarLink id={scholar ?? author}></ScholarLink>
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

		<!-- If the authenticated scholar is an editor or a role approver of one of the roles, then permit them to create new assignments -->
		{#if isEditor || roles.some((role) => isRoleApprover(role, volunteers, user.id))}
			<Form>
				<Tip
					>Add a new assignment to this submission. These are restricted to the roles for which you
					have assignment privileges.</Tip
				>
				<Row baseline>
					<select bind:value={newAssignmentRole}>
						<option value={undefined}>—</option>
						{#each isEditor ? roles : roles.filter( (role) => isRoleApprover(role, volunteers, user.id) ) as role}
							<option value={role.id}>{role.name}</option>
						{/each}
					</select>
					<TextField
						bind:text={newAssignmentScholar}
						placeholder="email or ORCID"
						valid={(emailOrORCID) =>
							emailOrORCID.length > 0 && !validEmail(emailOrORCID) && !validORCID(emailOrORCID)
								? 'Must be an email or ORCID'
								: undefined}
					></TextField>
					<Button
						tip="Create a new assignment for this scholar and this role."
						active={!newAssignmentSubmitting &&
							newAssignmentRole !== undefined &&
							(validEmail(newAssignmentScholar) || validORCID(newAssignmentScholar))}
						action={async () => {
							newAssignmentSubmitting = true;
							const role = roles.find((role) => role.id === newAssignmentRole);

							const { data: scholarID } = await db.findScholar(newAssignmentScholar);

							if (role === undefined) {
								newAssignmentError = 'You must select a valid role.';
								newAssignmentSubmitting = false;
								return undefined;
							} else if (scholarID === undefined) {
								newAssignmentError = 'No scholar with that email or ORCID exists.';
								newAssignmentSubmitting = false;
								return undefined;
							} else if (
								assignments.some((v) => v.scholar === scholarID && v.role === newAssignmentRole)
							) {
								newAssignmentError = 'This scholar is already assigned to this role.';
								newAssignmentSubmitting = false;
								return undefined;
							}

							return handle(
								db.createAssignment(submission.id, scholarID, role.id, false, true)
							).then(() => {
								newAssignmentRole = undefined;
								newAssignmentScholar = '';
								newAssignmentSubmitting = false;
							});
						}}>+ assignee</Button
					>
				</Row>
				{#if newAssignmentError !== undefined}<Feedback error>{newAssignmentError}</Feedback>{/if}
			</Form>
		{/if}

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
				{@const assigned = assignments.filter((a) => role.id === a.role && !a.bid)}
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
						<td class={!assignment.approved ? 'unapproved' : undefined}>
							<ScholarLink id={assignment.scholar} />
							{#if assignment.completed}<Tag>Completed</Tag>{:else if assignment.approved}<Tag
									>Assigned</Tag
								>{/if}</td
						>
						<td
							>{#if volunteer}{volunteer.expertise}{:else}{EmptyLabel}{/if}</td
						>
						<td>{getBalance(assignment.scholar)}</td>
						<td>
							<Row>
								{#if isApprover}
									{#if !assignment.completed}
										{#if assignment.approved}
											<Button
												tip="Remove this assignment"
												action={() =>
													handle(db.approveAssignment(assignment, false, role, user.id))}
												>Unassign</Button
											>
											{#if !assignment.completed}
												<Button
													tip="Mark this assignment complete and compensate the scholar for their work"
													action={() => handle(db.completeAssignment(assignment.id, user.id))}
													>Complete
												</Button>
											{/if}
										{:else}
											<Button
												tip="Reassign this scholar"
												action={() => handle(db.approveAssignment(assignment, true, role, user.id))}
												>Reassign</Button
											>
										{/if}
									{/if}
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

<style>
	.unapproved {
		text-decoration: line-through;
	}
</style>
