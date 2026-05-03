<script lang="ts">
	import type { SubmissionRow } from '$data/types';
	import Button from '$lib/components/Button.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import { DownLabel, PrivateLabel, SubmissionLabel, UpLabel } from '$lib/components/Labels';
	import Link from '$lib/components/Link.svelte';
	import Page from '$lib/components/Page.svelte';
	import Paragraph from '$lib/components/Paragraph.svelte';
	import Column from '$lib/components/Row.svelte';
	import ScholarLink from '$lib/components/ScholarLink.svelte';
	import Status from '$lib/components/Status.svelte';
	import SubmissionPreview from '$lib/components/SubmissionLink.svelte';
	import Table from '$lib/components/Table.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import Tip from '$lib/components/Tip.svelte';
	import Text from '$lib/locales/Text.svelte';
	import { getDB, NullUUID } from '$lib/data/CRUD';
	import canApproveAssignment from '$lib/data/canApproveAssignment';
	import isRoleApprover from '$lib/data/isRoleApprover';
	import { reloadOnChanges } from '$lib/data/SupabaseRealtime';
	import { getAuth } from '$routes/Auth.svelte';
	import { getLocaleContext } from '$routes/Contexts';
	import { handle } from '$routes/feedback.svelte';
	import { type PageData } from './$types';

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

	// Reload when the venue or its related data changes.
	reloadOnChanges('conflict_changes', [
		{ table: 'conflicts', filter: `scholar=eq.${auth().getUserID()}` }
	]);

	/** Get the current user ID state */
	const uid = $derived(auth().getUserID());

	/** True if the current user is an admin of this venue */
	const isAdmin = $derived(uid !== null && venue !== null && venue.admins.includes(uid));

	/** The roles to show, filtered by the which role the current scholar has */
	const visibleRoles = $derived(
		roles === null || volunteering === null
			? []
			: roles
					.toSorted((a, b) => a.priority - b.priority)
					.map((role) => {
						// See if this scholar has accepted this role.
						const hasRole = volunteering.some(
							(v) => v.scholarid === uid && v.roleid === role.id && v.accepted === 'accepted'
						);
						// Venue-wide check: could this scholar approve assignments for this
						// role on some submission? Used only for column visibility — the
						// per-submission gate below decides whether bid counts and approve
						// buttons actually render in each cell.
						const couldApprove =
							uid !== null && (isAdmin || isRoleApprover(role, volunteering, uid));

						return {
							...role,
							isVisible: isAdmin || role.biddable || hasRole || couldApprove,
							hasRole,
							couldApprove
						};
					})
					.filter((r) => r.isVisible)
	);


	/** State of sorting and filtering */
	let paymentSortPendingFirst = $state(true);
	let titleSortIncreasing = $state(true);
	let idSortIncreasing = $state(true);
	let sortOrder = $state<('payment' | 'title' | 'id' | 'created')[]>([
		'payment',
		'title',
		'id',
		'created'
	]);
	let filter = $state('');
	const locale = getLocaleContext();

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
				case 'created':
					subs.sort((a, b) => b.created_at.localeCompare(a.created_at));
					break;
			}
		}
		return subs;
	}

	function getSubmissionPaymentStatus(submission: SubmissionRow): number | undefined {
		if (transactions === null) return undefined;
		// NullUUID slots represent non-paying co-authors — no transaction is
		// expected for them, so they don't count toward the pending tally.
		const expected = submission.transactions.filter((t) => t !== NullUUID);
		const visible = expected
			.map((t) => transactions.find((tr) => tr.id === t))
			.filter((t) => t !== undefined);
		return expected.length - visible.length;
	}
</script>

{#if venue && conflicts}
	<Page
		icon={SubmissionLabel}
		title={(l) => l.page.submissions.title}
		breadcrumbs={[[`/venue/${venue.id}`, venue.title]]}
	>
		{#snippet details()}<Link to={venue.url}>{venue.url}</Link>{/snippet}

		<!-- Provide a clear link to the new submission page. -->
		<Paragraph text={(l) => l.page.submissions.paragraph.newSubmission} />

		{#if isAdmin}
			<Paragraph text={(l) => l.page.submissions.paragraph.bulkImport} />
		{/if}

		{#if uid}
			{#each visibleRoles.filter((r) => r.biddable) as role}
				<Tip>
					<Text path={(l) => l.page.submissions.tip.bid} inputs={{ role: role.name }} />
				</Tip>
			{/each}
		{/if}

		<TextField strings={(l) => l.page.submissions.field.filter} bind:text={filter}></TextField>

		{#if submissions === null}
			<Feedback error text={(l) => l.page.submissions.feedback.notLoaded}></Feedback>
		{:else if submissions.length === 0}
			<Feedback text={(l) => l.page.submissions.feedback.noSubmissions}></Feedback>
		{:else}
			{@const sorted = sortedAndFiltered(submissions)}
			{#if sorted.length === 0}
				<Feedback text={(l) => l.page.submissions.feedback.noneFiltered}></Feedback>
			{:else}
				<!-- Show a full-width table of all submissions, metadata about each, and bidding buttons if the current scholar is a volunteer. -->
				<Table full>
					{#snippet header()}
						<th
							>{locale().page.submissions.headers.payment}
							<Button
								small
								background={false}
								strings={(l) =>
									paymentSortPendingFirst
										? l.page.submissions.button.sortPaymentLast
										: l.page.submissions.button.sortPaymentFirst}
								action={() => {
									paymentSortPendingFirst = !paymentSortPendingFirst;
									sortOrder = [...sortOrder.filter((o) => o !== 'payment'), 'payment'];
								}}>{paymentSortPendingFirst ? DownLabel : UpLabel}</Button
							></th
						>
						<th
							>{locale().page.submissions.headers.title}
							<Button
								small
								background={false}
								strings={(l) =>
									titleSortIncreasing
										? l.page.submissions.button.sortTitleDesc
										: l.page.submissions.button.sortTitleAsc}
								action={() => {
									titleSortIncreasing = !titleSortIncreasing;
									sortOrder = [...sortOrder.filter((o) => o !== 'title'), 'title'];
								}}>{titleSortIncreasing ? DownLabel : UpLabel}</Button
							></th
						>
						<th>{locale().page.submissions.headers.expertise}</th>
						<th
							>{locale().page.submissions.headers.id}
							<Button
								small
								background={false}
								strings={(l) =>
									idSortIncreasing
										? l.page.submissions.button.sortIDDesc
										: l.page.submissions.button.sortIDAsc}
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
					{#each sorted as submission, index}
						{@const status = getSubmissionPaymentStatus(submission)}
						<tr data-testid="submission-{index}">
							<td>
								<!-- Couldn't load transactions? -->
								{#if status === undefined}
									{PrivateLabel}
								{:else if status === 0}
									<Status label={(l) => l.page.submissions.status.paid} />
								{:else}
									<Status
										good={false}
										label={(l) =>
											l.page.submissions.status.pending.replace('{count}', status.toString())}
									/>
								{/if}
							</td>
							<td>
								<Column>
									<SubmissionPreview {submission} />
									{#if uid && conflicts !== null && !conflicts.some((c) => c.scholarid === uid && c.submissionid === submission.id) && !submission.authors.includes(uid) && assignments !== null && !assignments.some((a) => a.submission === submission.id && a.scholar === uid)}
										<Button
											strings={(l) => l.page.submissions.button.declareConflict}
											action={() =>
												handle(db().declareConflict(uid, submission.id, 'Scholar declared'))}
										/>
									{/if}
								</Column>
							</td>
							<td>{submission.expertise}</td>
							<td>{submission.externalid}</td>
							<!-- If we have all the information, show metadata about bidding. -->
							{#each visibleRoles as role, roleIndex}
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
											{@const scholarAlreadyAssigned = approvedAssignments.some(
												(a) => a.scholar === uid
											)}
											{@const isApproverHere = canApproveAssignment(
												submission.id,
												role,
												roles,
												uid,
												isAdmin,
												assignments
											)}
											<!-- If the current scholar is an approver of this submission, show the current assignemnts -->
											{#if isApproverHere}
												<!-- Approver? Show the people assigned. -->
												{#each approvedAssignments as assignment}
													{#if assignment.scholar === uid}{locale().page.submissions.cell
															.you}{:else}<ScholarLink id={assignment.scholar} />{/if}
												{:else}
													<span><strong>0</strong> {locale().page.submissions.cell.assigned}</span>
												{/each}
											{/if}

											<!-- Show bidding if the role is biddable. Bidding closes when the
											     number of *approved* assignments reaches the role's desired count;
											     pending bids don't count toward closure. -->
											{#if role.biddable && !scholarAlreadyAssigned}
												{@const biddingOpen =
													approvedAssignments.length < role.desired_assignments}

												<!-- Approvers always see the pending bid count, regardless of whether
												     bidding is open or closed, so they can act on outstanding bids. -->
												{#if isApproverHere}
													<div>
														<strong>{bids.length}</strong>
														{locale().page.submissions.cell.bids}
													</div>
												{/if}

												{#if submission.authors.includes(uid) || conflicts.some((c) => c.scholarid === uid && c.submissionid === submission.id)}
													<!-- Can't bid if conflicted -->
													<div><strong>{locale().page.submissions.cell.conflicted}</strong></div>
												{:else if biddingOpen}
													{#if scholarsBid === undefined}
														<!-- No assignments? Allow bidding -->
														<Button
															testid={`bid-${index}-${roleIndex}`}
															strings={(l) => ({
																tip: l.page.submissions.button.bid.tip.replace(
																	'{role}',
																	role?.description ?? 'in this role'
																),
																label: l.page.submissions.button.bid.label
															})}
															action={() =>
																handle(db().createAssignment(submission.id, uid, role.id, true))}
														/>
													{:else if scholarsBid !== undefined && !scholarsBid.approved}
														<!-- Shown an unbid button if not yet approved -->
														<Button
															testid={`unbid-${index}-${roleIndex}`}
															strings={(l) => ({
																tip: l.page.submissions.button.unbid.tip.replace(
																	'{role}',
																	role?.description ?? 'in this role'
																),
																label: l.page.submissions.button.unbid.label
															})}
															action={() => handle(db().deleteAssignment(scholarsBid.id))}
														/>
													{/if}
												{:else}
													<div><strong>{locale().page.submissions.cell.biddingClosed}</strong></div>
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
	</Page>
{/if}
