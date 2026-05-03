<script lang="ts">
	import type { RoleID, RoleRow, ScholarID } from '$data/types';
	import Button from '$lib/components/Button.svelte';
	import Checkbox from '$lib/components/Checkbox.svelte';
	import EditableText from '$lib/components/EditableText.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import Form from '$lib/components/Form.svelte';
	import {
		EditLabel,
		EmptyLabel,
		ErrorLabel,
		ScholarLabel,
		SubmissionLabel,
		VenueLabel
	} from '$lib/components/Labels';
	import Link from '$lib/components/Link.svelte';
	import Options from '$lib/components/Options.svelte';
	import Page from '$lib/components/Page.svelte';
	import Row from '$lib/components/Row.svelte';
	import ScholarLink from '$lib/components/ScholarLink.svelte';
	import Status from '$lib/components/Status.svelte';
	import Subheader from '$lib/components/Subheader.svelte';
	import Table from '$lib/components/Table.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import Tip from '$lib/components/Tip.svelte';
	import Tokens from '$lib/components/Tokens.svelte';
	import VenueLink from '$lib/components/VenueLink.svelte';
	import { getDB, NullUUID } from '$lib/data/CRUD';
	import Scholar from '$lib/data/Scholar.svelte';
	import type LocaleText from '$lib/locales/Locale';
	import Text from '$lib/locales/Text.svelte';
	import { validEmail, validORCID } from '$lib/validation';
	import { getLocaleContext } from '$routes/Contexts';
	import { handle } from '$routes/feedback.svelte';
	import { type PageData } from './$types';

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
		scholar,
		/** The submission types for this venue */
		submissionTypes
	} = $derived(data);

	/** Get the database connection */
	const db = getDB();
	const locale = getLocaleContext();

	/** Whether the current scholar is an editor */
	let isAdmin = $derived(venue !== null && scholar !== null && venue.admins.includes(scholar.id));

	let submissionType = $derived(
		(submission !== null && submissionTypes !== null
			? (submissionTypes.find((t) => t.id === submission.submission_type)?.id ??
				submissionTypes[0].id)
			: undefined) ?? NullUUID
	);

	/** Whether the current scholar has the highest rank role on this submission */
	let isEditor = $derived(
		assignments?.some(
			(a) =>
				roles !== null &&
				a.scholar === scholar?.id &&
				roles.some((r) => r.id === a.role && r.priority === 0)
		)
	);

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
		submission !== null && scholar !== null && submission.authors.includes(scholar.id)
	);

	/** Assignment if the authenticated scholar to this submission */
	let scholarAssignments = $derived(
		scholar !== null && assignments !== null
			? assignments.filter((a) => a.scholar === scholar.id && a.approved)
			: undefined
	);

	/** Whether the current scholar is assigned to this submission */
	let isAssigned = $derived(scholarAssignments !== undefined);

	/** What role does this assignment approve, if any */
	let rolesScholarCanApprove = $derived(
		scholarAssignments !== undefined && roles !== null
			? roles.filter((r) => scholarAssignments.some((a) => a.role === r.approver))
			: []
	);

	let scholarAssignmentRoles = $derived(
		scholarAssignments !== undefined && roles !== null
			? scholarAssignments
					.map((a) => roles.find((r) => r.id === a.role))
					.filter((r): r is RoleRow => r !== undefined)
			: []
	);

	/** State for the assignment form */
	let newAssignmentRole = $state<RoleID | undefined>(undefined);
	let newAssignmentScholar = $state<string>('');
	let newAssignmentSubmitting = $state(false);
	let newAssignmentError: ((l: LocaleText) => string) | undefined = $state(undefined);

	function getVolunteer(role: RoleID, scholar: ScholarID) {
		return volunteers?.find((v) => v.roleid === role && v.scholarid === scholar);
	}

	function getBalance(scholar: ScholarID) {
		return balances?.find((balance) => balance.scholar === scholar)?.count ?? 0;
	}
</script>

{#if submission === null || venue === null || roles === null || scholar === null || assignments === null || authors === null || volunteers === null || submissionTypes === null}
	<Page
		icon={ErrorLabel}
		title={(l) => l.page.submission.title}
		breadcrumbs={[
			[`/venue/${venue?.id}`, venue?.title ?? ''],
			[`/venue/${venue?.id}/submissions`, 'Submissions']
		]}
	>
		<Feedback error text={(l) => l.page.submission.feedback.notLoaded}></Feedback>
	</Page>
{:else if !isAuthor && !isAssigned}
	<Page
		icon={ErrorLabel}
		title={(l) => l.page.submission.title}
		breadcrumbs={[
			[`/venue/${venue?.id}`, venue?.title ?? ''],
			[`/venue/${venue?.id}/submissions`, 'Submissions']
		]}
	>
		<Feedback error text={(l) => l.page.submission.feedback.confidential}></Feedback>
	</Page>
{:else}
	<Page
		icon={SubmissionLabel}
		title={submission.title}
		breadcrumbs={[
			[`/venue/${submission.venue}`, venue?.title ?? ''],
			[`/venue/${submission.venue}/submissions`, 'Submissions']
		]}
		edit={// Only editors can update the submission title.
		isEditor
			? {
					placeholder: (l) => l.page.venue.field.name.placeholder,
					valid: (text) =>
						text.trim().length === 0 ? (l) => l.page.venue.field.name.invalid : undefined,
					update: (text) => db().updateSubmissionTitle(submission.id, text)
				}
			: undefined}
	>
		{#snippet subtitle()}
			{#if isEditor}
				<Options
					strings={(l) => l.page.submission.options.submissionType}
					bind:value={submissionType}
					options={submissionTypes.map((type) => ({ value: type.id, label: type.name }))}
					onChange={(typeID) =>
						typeID !== undefined ? db().updateSubmissionType(submission.id, typeID) : undefined}
				></Options>
			{:else if submissionType}{submissionTypes.find((t) => t.id === submissionType)
					?.name}{:else}<Text path={(l) => l.page.submission.subtitle} />{/if}
		{/snippet}
		{#snippet details()}
			{#if previous}
				<Link to="/venue/{venue.id}/submission/{previous.id}">{previous.externalid}</Link>→
			{/if}
			{submission.externalid}
			{#if done}
				<Status good={false} label={(l) => l.page.submission.status.done} />
			{:else}
				<Status label={(l) => l.page.submission.status.reviewing} />
			{/if}
		{/snippet}

		<!-- Only editors can update the status of a submission -->
		{#if isEditor}
			<Checkbox
				on={done}
				change={(on) => db().updateSubmissionStatus(submission.id, on ? 'done' : 'reviewing')}
				label={(l) => l.page.submission.checkbox.reviewComplete}
			/>
		{/if}

		<Subheader icon={ScholarLabel} text={(l) => l.page.submission.header.authors}></Subheader>

		{#each submission.authors as author, idx}
			{@const authorIndex = authors.findIndex((a) => a.id === author)}
			{@const payment = authorIndex > -1 ? submission.payments[authorIndex] : undefined}
			{@const transactionId = submission.transactions[idx]}
			{@const transaction =
				authorTransactions === null || authorIndex === undefined
					? undefined
					: authorTransactions[authorIndex]}
			{@const scholar = authorIndex > -1 ? new Scholar(authors[authorIndex]) : undefined}
			<Row>
				{#if authorIndex === undefined}
					<Feedback error text={(l) => l.page.submission.feedback.missingAuthors}></Feedback>
				{:else if isEditor || isAuthor || (isAssigned && !scholarAssignmentRoles.some((r) => r.anonymous_authors))}
					<ScholarLink id={scholar ?? author}></ScholarLink>
					{#if payment !== undefined}
						{#if transactionId === NullUUID}
							{locale().page.submission.cell.nonPaying}
						{:else if transaction === undefined}
							<Status good={false} label={(l) => l.page.submission.status.unknownTransaction} />
						{:else}
							{#if transaction.status === 'proposed'}
								{locale().page.submission.cell.proposesToPay}
							{:else if transaction.status === 'approved'}
								{locale().page.submission.cell.paid}
							{:else if transaction.status === 'canceled'}
								{locale().page.submission.cell.declinedToPay}
							{/if}
							<Tokens amount={payment} />
						{/if}
					{/if}
				{:else}
					<em>{locale().page.submission.cell.anonymized}</em>
				{/if}
			</Row>
		{:else}
			<Feedback error text={(l) => l.page.submission.feedback.noAuthors} />
		{/each}

		<Subheader icon={VenueLabel} text={(l) => l.page.submission.header.venue}></Subheader>
		<VenueLink id={venue.id} name={venue.title} />

		<Subheader icon={EditLabel} text={(l) => l.page.submission.header.expertise}></Subheader>
		{#if isAuthor}
			<EditableText
				strings={(l) => ({
					label: 'Expertise',
					placeholder: 'Keywords and phrases describing your expertise.'
				})}
				text={submission.expertise ?? ''}
				edit={(text) =>
					db().updateSubmissionExpertise(submission.id, text.trim().length === 0 ? null : text)}
			/>
		{:else if submission.expertise}
			{submission.expertise}
		{:else}
			<Feedback text={(l) => l.page.submission.feedback.noExpertise} />
		{/if}

		<Subheader icon={EditLabel} text={(l) => l.page.submission.header.note}></Subheader>
		{#if isAuthor || isAdmin}
			<EditableText
				strings={(l) => l.page.submission.field.note}
				text={submission.note ?? ''}
				edit={(text) =>
					db().updateSubmissionNote(submission.id, text.trim().length === 0 ? null : text)}
			/>
		{:else if submission.note}
			{submission.note}
		{:else}
			<Feedback text={(l) => l.page.submission.feedback.noNote} />
		{/if}

		<Subheader icon={EditLabel} text={(l) => l.page.submission.header.assignments}></Subheader>

		<!-- If the authenticated scholar is an editor or a role approver of one of the roles, then permit them to create new assignments -->
		{#if isEditor || rolesScholarCanApprove.length > 0}
			<Form>
				<Tip><Text path={(l) => l.page.submission.tip.newAssignment} /></Tip>
				<Options
					strings={(l) => l.page.submission.options.assignmentRole}
					bind:value={newAssignmentRole}
					options={[
						...(isAdmin ? roles : rolesScholarCanApprove).map((role) => ({
							label: role.name,
							value: role.id
						}))
					]}
				/>
				<TextField
					bind:text={newAssignmentScholar}
					strings={(l) => l.page.submission.field.newAssignment}
					valid={(emailOrORCID) =>
						emailOrORCID.length > 0 && !validEmail(emailOrORCID) && !validORCID(emailOrORCID)
							? (l) => l.page.submission.field.newAssignment.invalid
							: undefined}
				></TextField>
				<Button
					testid="new-assignment"
					strings={(l) => l.page.submission.button.createAssignment}
					active={!newAssignmentSubmitting &&
						newAssignmentRole !== undefined &&
						(validEmail(newAssignmentScholar) || validORCID(newAssignmentScholar))}
					action={async () => {
						newAssignmentSubmitting = true;
						const role = roles.find((role) => role.id === newAssignmentRole);

						const { data: scholarID } = await db().findScholar(newAssignmentScholar);

						if (role === undefined) {
							newAssignmentError = (l) => l.page.submission.feedback.invalidRole;
							newAssignmentSubmitting = false;
							return undefined;
						} else if (scholarID === undefined) {
							newAssignmentError = (l) => l.page.submission.feedback.scholarNotFound;
							newAssignmentSubmitting = false;
							return undefined;
						} else if (
							assignments.some((v) => v.scholar === scholarID && v.role === newAssignmentRole)
						) {
							newAssignmentError = (l) => l.page.submission.feedback.alreadyAssigned;
							newAssignmentSubmitting = false;
							return undefined;
						}

						return handle(
							db().createAssignment(submission.id, scholarID, role.id, false, true)
						).then(() => {
							newAssignmentRole = undefined;
							newAssignmentScholar = '';
							newAssignmentSubmitting = false;
						});
					}}>+ assignee</Button
				>
				{#if newAssignmentError !== undefined}<Feedback error text={newAssignmentError} />{/if}
			</Form>
		{/if}

		<Table full>
			{#snippet header()}
				<th>{locale().page.submission.headers.role}</th>
				<th>{locale().page.submission.headers.scholar}</th>
				<th>{locale().page.submission.headers.expertise}</th>
				<th>{locale().page.submission.headers.balance}</th>
				<th>{locale().page.submission.headers.action}</th>
			{/snippet}

			<!-- Sort roles by priority -->
			{#each roles.toSorted((a, b) => a.priority - b.priority) as role}
				{@const assigned = assignments.filter((a) => role.id === a.role && !a.bid)}
				<!-- The bidding assignments are those that match this role and aren't approved. We sort them by the balances of the corresponding scholar. -->
				{@const bidded = assignments
					.filter((a) => role.id === a.role && a.bid && !a.approved)
					.toSorted((a, b) => getBalance(a.scholar) - getBalance(b.scholar))}
				{@const isApprover =
					isEditor || (scholar !== null && rolesScholarCanApprove.some((r) => r.id === role.id))}
				{#each assigned as assignment}
					{@const volunteer = getVolunteer(role.id, assignment.scholar)}
					<tr>
						<td>{role.name}</td>
						<td class={!assignment.approved ? 'unapproved' : undefined}>
							{#if assignment.scholar === scholar.id}{locale().page.submission.cell
									.you}{:else}<ScholarLink id={assignment.scholar} />{/if}
							{#if assignment.completed}<Status
									label={(l) => l.page.submission.status.completed}
								/>{:else if assignment.approved}<Status
									good={false}
									label={(l) => l.page.submission.status.incomplete}
								/>{:else}<Status
									good={false}
									label={(l) => l.page.submission.status.unapproved}
								/>{/if}</td
						>
						<td
							>{#if volunteer}{volunteer.expertise}{:else}{EmptyLabel}{/if}</td
						>
						<td><Tokens amount={getBalance(assignment.scholar)} /></td>
						<td>
							<Row>
								{#if isApprover}
									{#if !assignment.completed}
										{#if assignment.approved}
											<Button
												strings={(l) => l.page.submission.button.unassign}
												action={() =>
													handle(db().approveAssignment(assignment, false, role, scholar.id))}
											/>
											{#if !assignment.completed}
												<Button
													strings={(l) => l.page.submission.button.complete}
													action={() => handle(db().completeAssignment(assignment.id, scholar.id))}
												/>
											{/if}
										{:else}
											<Button
												strings={(l) => l.page.submission.button.approve}
												action={() =>
													handle(db().approveAssignment(assignment, true, role, scholar.id))}
											/>
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
							<td><Tokens amount={getBalance(assignment.scholar)} /></td>
							<td>
								<Row>
									{#if assignment.bid}
										<Button
											strings={(l) => l.page.submission.button.approveBid}
											action={() =>
												scholar
													? handle(db().approveAssignment(assignment, true, role, scholar.id))
													: null}
										/>
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
		font-style: italic;
	}
</style>
