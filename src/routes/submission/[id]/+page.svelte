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
	import { getAuth } from '../../Auth.svelte';
	import Link from '$lib/components/Link.svelte';
	import Status from '$lib/components/Status.svelte';
	import Checkbox from '$lib/components/Checkbox.svelte';
	import Tag from '$lib/components/Tag.svelte';
	import Table from '$lib/components/Table.svelte';
	import Button from '$lib/components/Button.svelte';
	import { handle } from '../../feedback.svelte';

	let { data }: { data: PageData } = $props();
	const {
		submission,
		venue,
		authors,
		previous,
		transactions,
		assignments,
		volunteers,
		roles,
		scholarRoles
	} = $derived(data);

	const db = getDB();
	const auth = getAuth();
	const user = $derived(auth.getUserID());
	const authorTransactions = $derived(
		submission === null || transactions === null
			? null
			: submission.transactions.map((id) => transactions.find((t) => t.id === id))
	);
	const done = $derived(submission?.status === 'done');

	let isEditor = $derived(venue !== null && user !== null && venue.editors.includes(user));

	let isAuthor = $derived(
		submission !== null && user !== null && submission.authors.includes(user)
	);

	let isAssigned = $derived(volunteers?.find((v) => v.scholarid === user) !== undefined);

	// Can see assignments if the user is the editor or has a role or has a role for the submission.
	let canSeeAssignments = $derived(isEditor || isAssigned);
</script>

{#if submission === null}
	<Page
		title="Submission"
		breadcrumbs={[
			[`/venue/${venue?.id}`, venue?.title ?? ''],
			[`/venue/${venue?.id}/submissions`, 'Submissions']
		]}
	>
		<Feedback error>This submission does not exist.</Feedback>
	</Page>
{:else if !isEditor && !isAuthor && !isAssigned}
	<Page
		title="Submission"
		breadcrumbs={[
			[`/venue/${venue?.id}`, venue?.title ?? ''],
			[`/venue/${venue?.id}/submissions`, 'Submissions']
		]}
	>
		<Feedback error>You are not authorized to view this submission.</Feedback>
	</Page>
{:else}
	<Page
		title={submission.title}
		breadcrumbs={[
			[`/venue/${submission.venue}`, venue?.title ?? ''],
			[`/venue/${submission.venue}/submissions`, 'Submissions']
		]}
		edit={isAuthor || isEditor
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

		{#if isEditor}
			<Checkbox
				on={!done}
				change={(on) => db.updateSubmissionStatus(submission.id, on ? 'reviewing' : 'done')}
				>This submission is still in review.</Checkbox
			>
		{/if}

		<h2>Authors</h2>

		{#if authors}
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
					{:else}
						<ScholarLink id={author}></ScholarLink>
						{#if (isEditor || isAuthor) && payment !== undefined}
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
					{/if}
				</Row>
			{/each}
		{:else}{/if}

		<h2>Venue</h2>
		{#if venue}
			<VenueLink id={venue.id} name={venue.title} />
		{/if}

		<h2>Expertise</h2>
		{#if isAuthor}
			<EditableText
				text={submission.expertise ?? ''}
				placeholder="Expertise"
				edit={(text) =>
					db.updateSubmissionExpertise(submission.id, text.trim().length === 0 ? null : text)}
			/>
		{:else if submission.expertise}{submission.expertise}{:else}<Feedback
				>No expertise provided</Feedback
			>{/if}

		<h2>
			Assignments {#if isEditor}
				<Tag>editor</Tag>{/if}
		</h2>

		<h3>Editor</h3>

		{#if venue !== null && venue.editors.length > 0}
			{#each venue.editors as editor}
				<ScholarLink id={editor}></ScholarLink>
			{/each}
		{:else}
			<Feedback error>No editor assigned.</Feedback>
		{/if}

		<!-- If there are assignments to show, show them. -->
		{#if venue !== null && canSeeAssignments && user !== null && roles}
			{#if roles && assignments}
				{#each roles.toSorted((a, b) => a.priority - b.priority) as role}
					{@const assigned = assignments.filter((a) => role.id === a.role && a.approved)}
					{@const bidded = assignments.filter((a) => role.id === a.role && a.bid && !a.approved)}
					<h3>{role.name}</h3>
					{#each assigned as assignment}
						<Row>
							<ScholarLink id={assignment.scholar} /><Tag>Assigned</Tag>
							<Button
								tip="Remove this assignment"
								action={() => handle(db.approveAssignment(assignment.id, false))}>Unassign</Button
							>
						</Row>
					{:else}
						<Feedback>No one is assigned.</Feedback>
					{/each}
					<!-- Is the current scholar an approver of this role? The bids so they can be approved. -->
					{#if bidded.length > 0 && (isEditor || (role.approver !== null && scholarRoles.includes(role.approver)))}
						<Table full>
							{#snippet header()}
								<th>scholar</th><th>expertise</th><th>bids</th>
							{/snippet}
							{#each bidded as assignment}
								{@const volunteer = volunteers?.find((v) => v.scholarid === assignment.scholar)}
								<tr>
									<td><ScholarLink id={assignment.scholar} /></td>
									<td
										>{#if volunteer}{volunteer.expertise}{:else}<Feedback inline error
												>Unknown</Feedback
											>{/if}</td
									>
									<td>
										<Row>
											<ScholarLink id={assignment.scholar} />
											{#if assignment.bid}
												<Button
													tip="Accept this bid, assigning this scholar to this role for this submission."
													action={() => handle(db.approveAssignment(assignment.id, true))}
													>Assign</Button
												>
											{/if}
										</Row>
									</td>
								</tr>
							{/each}
						</Table>
					{:else}
						<Feedback error>No visible bids.</Feedback>
					{/if}
				{:else}{/each}
			{/if}
		{/if}
	</Page>
{/if}
