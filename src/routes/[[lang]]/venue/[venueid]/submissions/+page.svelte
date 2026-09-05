<script lang="ts">
	import { page } from '$app/state';
	import { venuePath } from '$lib/data/venuePath';
	import Button from '$lib/components/Button.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import {
		DownLabel,
		EmptyLabel,
		PrivateLabel,
		SubmissionLabel,
		UnknownLabel,
		UpLabel
	} from '$lib/components/Labels';
	import Link from '$lib/components/Link.svelte';
	import Page from '$lib/components/Page.svelte';
	import Paragraph from '$lib/components/Paragraph.svelte';
	import Column from '$lib/components/Row.svelte';
	import ScholarLink from '$lib/components/ScholarLink.svelte';
	import Status from '$lib/components/Status.svelte';
	import SubmissionPreview from '$lib/components/SubmissionLink.svelte';
	import Table from '$lib/components/Table.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import Checkbox from '$lib/components/Checkbox.svelte';
	import Tip from '$lib/components/Tip.svelte';
	import Form from '$lib/components/Form.svelte';
	import Options from '$lib/components/Options.svelte';
	import type Locale from '$lib/locales/Locale';
	import Text from '$lib/locales/Text.svelte';
	import { validEmail, validORCID } from '$lib/validation';
	import { getDB } from '$lib/data/CRUD';
	import { alreadyAssigned } from '$lib/data/assignees';
	import canApproveAssignment from '$lib/data/canApproveAssignment';
	import canClaimEditor from '$lib/data/canClaimEditor';
	import isRoleApprover from '$lib/data/isRoleApprover';
	import { submissionsView } from '$lib/data/sortSubmissions';
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
		/** Per submission, whether anyone holds the venue's editor role on it */
		submissionEditors,
		/** All transctions for all submissions in this venue */
		transactions,
		/** The conflicts for the current scholar */
		conflicts,
		/** Venue-defined preference levels (empty if not configured) */
		preferenceLevels,
		/** Names of scholars referenced as authors or assigned reviewers, for the filter */
		scholars
	} = $derived(data);

	/** A payment-free venue has no currency, so its submissions have nothing to
	 * report and the column asks a question that does not apply. Every other
	 * payment-aware page already derives this; this one never did, which is how it
	 * came to show a green "paid" badge on every submission at a venue that
	 * charges nothing. */
	const showPayment = $derived(venue ? !venue.payment_free : true);

	/** Lowercase name lookup for use in the submissions filter. */
	const scholarName = $derived(
		new Map((scholars ?? []).map((s) => [s.id, (s.name ?? '').toLowerCase()]))
	);

	/** Role lookup so we can honor `role.anonymous_authors` when deciding
	 * whether to include author names in the search blob. */
	const rolesById = $derived(new Map((roles ?? []).map((r) => [r.id, r])));

	/** The venue's editor role, if it has one. Claiming is only ever about this role —
	 * priority 0 is what the database checks when deciding who edits a submission. */
	const editorRole = $derived((roles ?? []).find((r) => r.priority === 0));

	/** The submissions someone is already editing. Null until it loads, so the flag stays
	 * off rather than briefly claiming every submission needs an editor. */
	const submissionsWithEditor = $derived(
		submissionEditors === null
			? null
			: new Set(submissionEditors.filter((s) => s.has_editor).map((s) => s.submission))
	);

	const sortedLevels = $derived([...(preferenceLevels ?? [])].sort((a, b) => a.rank - b.rank));

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
	/** Default to newest-first (descending). */
	let createdSortLatestFirst = $state(true);
	let sortOrder = $state<('payment' | 'title' | 'id' | 'created')[]>([
		'payment',
		'title',
		'id',
		'created'
	]);
	// svelte-ignore state_referenced_locally
	let filter = $state(page.url.searchParams.get('filter') ?? '');
	/** Narrow the list to submissions nobody is editing yet — the editorial round's
	 * first question, and the one the list could not answer before. */
	let needsEditorOnly = $state(false);
	const locale = getLocaleContext();

	/** The submissions-list view logic — search matching, the author-visibility
	 * gate, payment status, and the sort/filter pipeline — lives in
	 * $lib/data/sortSubmissions so its ordering and privacy rules are testable.
	 * `now` is read here so the done-visibility window follows the clock. */
	const view = $derived(
		submissionsView({
			uid,
			isAdmin,
			assignments,
			rolesById,
			submissionsWithEditor,
			scholarName,
			conflicts,
			transactions,
			doneVisibilityDays: venue?.done_visibility_days ?? null,
			filter,
			needsEditorOnly,
			now: Date.now(),
			sortOrder,
			paymentSortPendingFirst,
			titleSortIncreasing,
			idSortIncreasing,
			createdSortLatestFirst
		})
	);

	function formatDate(iso: string): string {
		return new Date(iso).toLocaleDateString();
	}

	// ---- Batch assignment ----------------------------------------------------
	// Assigning one scholar to several submissions (the monthly AE round, or an
	// editor self-assigning) otherwise meant opening each submission in turn.
	// Resolve the scholar and role once here, then assign per row below.

	/** The roles this scholar could assign someone to somewhere in this venue. */
	const assignableRoles = $derived(
		isAdmin ? visibleRoles : visibleRoles.filter((role) => role.couldApprove)
	);

	let batchRole = $state<string | undefined>(undefined);
	let batchScholar = $state('');
	/** The resolved scholar id; null until the text above is looked up. */
	let batchScholarID = $state<string | null>(null);
	let batchResolving = $state(false);
	let batchError = $state<((l: Locale) => string) | undefined>(undefined);

	/** Re-resolving is required whenever the text changes, so a stale id can't
	 * be assigned to someone the editor no longer has on screen. */
	$effect(() => {
		batchScholar;
		batchScholarID = null;
	});

	async function resolveBatchScholar() {
		batchResolving = true;
		batchError = undefined;
		const { data } = await db().findScholar(batchScholar);
		if (data === undefined) batchError = (l) => l.page.submissions.feedback.scholarNotFound;
		else batchScholarID = data;
		batchResolving = false;
	}
</script>

{#if venue && conflicts}
	<Page
		icon={SubmissionLabel}
		title={(l) => l.page.submissions.title}
		breadcrumbs={[[`/venue/${venuePath(venue)}`, venue.title]]}
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

		<TextField
			testid="submissions-filter"
			strings={(l) => l.page.submissions.field.filter}
			bind:text={filter}
		></TextField>

		<Checkbox
			testid="submissions-needs-editor-filter"
			label={(l) => l.page.submissions.checkbox.needsEditor}
			bind:on={needsEditorOnly}
		/>

		<!-- Assign one scholar across many submissions without opening each one. -->
		{#if uid && assignableRoles.length > 0}
			<Form>
				<Tip><Text path={(l) => l.page.submissions.tip.batchAssign} /></Tip>
				<Options
					strings={(l) => l.page.submissions.options.batchRole}
					bind:value={batchRole}
					options={assignableRoles.map((role) => ({ label: role.name, value: role.id }))}
				/>
				<TextField
					testid="batch-assign-scholar"
					strings={(l) => l.page.submissions.field.batchAssign}
					bind:text={batchScholar}
					valid={(emailOrORCID) =>
						emailOrORCID.length > 0 && !validEmail(emailOrORCID) && !validORCID(emailOrORCID)
							? (l) => l.page.submissions.field.batchAssign.invalid
							: undefined}
				/>
				<Button
					testid="batch-assign-find"
					strings={(l) => l.page.submissions.button.batchFind}
					active={!batchResolving &&
						batchScholarID === null &&
						batchRole !== undefined &&
						(validEmail(batchScholar) || validORCID(batchScholar))}
					action={resolveBatchScholar}
				/>
				{#if batchError !== undefined}
					<Feedback error text={batchError} />
				{:else if batchScholarID !== null}
					<Feedback text={(l) => l.page.submissions.feedback.batchReady} />
				{/if}
			</Form>
		{/if}

		{#if submissions === null}
			<Feedback error text={(l) => l.page.submissions.feedback.notLoaded}></Feedback>
		{:else if submissions.length === 0}
			<Feedback text={(l) => l.page.submissions.feedback.noSubmissions}></Feedback>
		{:else}
			{@const sorted = view.sortedAndFiltered(submissions)}
			{#if sorted.length === 0}
				<Feedback text={(l) => l.page.submissions.feedback.noneFiltered}></Feedback>
			{:else}
				<!-- Show a full-width table of all submissions, metadata about each, and bidding buttons if the current scholar is a volunteer. -->
				<Table full>
					{#snippet header()}
						{#if showPayment}
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
						{/if}
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
						<th>{locale().page.submissions.headers.authors}</th>
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
						<th
							>{locale().page.submissions.headers.created}
							<Button
								small
								background={false}
								strings={(l) =>
									createdSortLatestFirst
										? l.page.submissions.button.sortCreatedOldest
										: l.page.submissions.button.sortCreatedNewest}
								action={() => {
									createdSortLatestFirst = !createdSortLatestFirst;
									sortOrder = [...sortOrder.filter((o) => o !== 'created'), 'created'];
								}}>{createdSortLatestFirst ? DownLabel : UpLabel}</Button
							></th
						>
						<th>{locale().page.submissions.headers.progress}</th>
						<!-- If bidding is enabled, add column for each of the scholar's volunteer roles -->
						{#each visibleRoles as role}
							<th>{role.name}</th>
						{/each}
					{/snippet}
					{#each sorted as submission, index}
						{@const status = view.paymentStatus(submission)}
						<tr data-testid="submission-{index}">
							{#if showPayment}
								<td>
									{#if status.state === 'unknown'}
										<!-- Couldn't load transactions. -->
										{PrivateLabel}
									{:else if status.state === 'free'}
										<!-- Nothing was ever charged: imported, or a zero-cost type. Neither
										     colour of the good/bad pair fits, because this is a fact about the
										     submission rather than a verdict on anybody. -->
										<Status
											neutral
											testid="submission-{index}-payment"
											label={(l) => l.page.submissions.status.free}
										/>
									{:else if status.state === 'paid'}
										<Status
											testid="submission-{index}-payment"
											label={(l) => l.page.submissions.status.paid}
										/>
									{:else}
										<Status
											good={false}
											testid="submission-{index}-payment"
											label={(l) =>
												l.page.submissions.status.pending.replace(
													'{count}',
													status.count.toString()
												)}
										/>
									{/if}
								</td>
							{/if}
							<td class:highlight={view.matches(submission.title)}>
								<Column>
									<SubmissionPreview {submission} />
									{#if uid && conflicts !== null && !conflicts.some((c) => c.scholarid === uid && c.submissionid === submission.id) && !submission.authors.includes(uid) && assignments !== null && !assignments.some((a) => a.submission === submission.id && a.scholar === uid)}
										<Button
											strings={(l) => l.page.submissions.button.declareConflict}
											testid="declare-conflict"
											action={() =>
												handle(db().declareConflict(uid, submission.id, 'Scholar declared'))}
										/>
									{/if}
								</Column>
							</td>
							<td
								class:highlight={view.canSeeAuthors(submission) &&
									view.anyScholarMatches(submission.authors)}
							>
								{#if view.canSeeAuthors(submission)}
									{#each submission.authors as authorID, i}
										{#if i > 0},
										{/if}<ScholarLink id={authorID} />
									{/each}
								{:else}
									<!-- Deliberately withheld, which is a different fact from the
									     "couldn't load" and "not signed in" cases that also use
									     PrivateLabel on this page. The lock says which one this is;
									     the title carries the word for anyone who can't read the
									     glyph. -->
									<span title={locale().page.submissions.cell.anonymized}>{UnknownLabel}</span>
								{/if}
							</td>
							<!-- Expertise is what a bidder reads to decide whether to bid, and it
							     is nullable — the detail page writes null back for empty input. An
							     empty cell looked broken rather than unanswered. -->
							<td>{submission.expertise?.trim() ? submission.expertise : EmptyLabel}</td>
							{#if view.canSeeAuthors(submission)}
								<td class:highlight={view.matches(submission.externalid)}
									>{submission.externalid}</td
								>
							{:else}
								<!-- The manuscript ID is the key this paper is filed under in the
								     venue's own reviewing system, so it leads back to the authors
								     the column above is hiding. -->
								<td
									><span title={locale().page.submissions.cell.anonymized}>{UnknownLabel}</span></td
								>
							{/if}
							<td>{formatDate(submission.created_at)}</td>
							<td>
								{#if submission.status === 'done'}
									<Status label={(l) => l.page.submissions.status.done} />
								{:else}
									<Status good={false} label={(l) => l.page.submissions.status.reviewing} />
									<!-- Nobody holds the editor role on this one, so no assignment on it can
									     be approved and it cannot be marked done. Shown next to the status
									     because it is a fact about the submission's progress, not about the
									     viewer's own work. -->
									{#if view.needsEditor(submission)}
										<Status
											good={false}
											testid="needs-editor-{index}"
											label={(l) => l.page.submissions.status.needsEditor}
										/>
										{#if editorRole && canClaimEditor(editorRole, uid, volunteering, submissionsWithEditor?.has(submission.id))}
											<Button
												small
												testid="claim-editor-{index}"
												strings={(l) => l.page.submissions.button.claimEditor}
												action={() =>
													handle(
														db().createAssignment(submission.id, uid!, editorRole.id, false, true)
													)}
											/>
										{/if}
									{/if}
								{/if}
							</td>
							<!-- If we have all the information, show metadata about bidding. -->
							{#each visibleRoles as role, roleIndex}
								<!-- This cell should show all actions available for this role and submission, based on the current scholar's role. -->
								{@const roleScholarIDs =
									assignments
										?.filter((a) => a.submission === submission.id && a.role === role.id)
										.map((a) => a.scholar) ?? []}
								<td class:highlight={view.anyScholarMatches(roleScholarIDs)}>
									<Column>
										{#if uid}
											{@const roleAssignments = assignments?.filter(
												(a) => a.submission === submission.id && a.role === role.id
											)}
											{@const approvedAssignments =
												roleAssignments?.filter((a) => a.approved) ?? []}
											{@const bids = roleAssignments?.filter((a) => a.bid && !a.approved) ?? []}
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

												<!-- Batch assign: one click per submission once the scholar and
												     role are resolved above. Hidden where they already hold this
												     role, since a duplicate would just add a second row. -->
												{#if batchScholarID !== null && batchRole === role.id && !alreadyAssigned(assignments, submission.id, batchScholarID, role.id)}
													<Button
														testid={`batch-assign-${index}-${roleIndex}`}
														strings={(l) => l.page.submissions.button.batchAssign}
														action={() =>
															handle(
																db().createAssignment(
																	submission.id,
																	batchScholarID!,
																	role.id,
																	false,
																	true
																)
															)}
													/>
												{/if}
											{/if}

											<!-- Show bidding if the role is biddable. Bidding closes when the
											     number of *approved* assignments reaches the role's desired count;
											     pending bids don't count toward closure. -->
											{#if role.biddable && !scholarAlreadyAssigned}
												{@const biddingOpen = approvedAssignments.length < role.desired_assignments}

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
														{#if sortedLevels.length === 0}
															<!-- No preference levels: legacy yes/no bid -->
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
														{:else}
															<!-- Preference levels defined: one bid button per level -->
															{#each sortedLevels as level}
																<Button
																	testid={`bid-${index}-${roleIndex}-${level.rank}`}
																	strings={(l) => ({
																		tip: l.page.submissions.button.bid.tip.replace(
																			'{role}',
																			role?.description ?? 'in this role'
																		),
																		label: level.label
																	})}
																	action={() =>
																		handle(
																			db().createAssignment(
																				submission.id,
																				uid,
																				role.id,
																				true,
																				false,
																				level.id
																			)
																		)}
																/>
															{/each}
														{/if}
													{:else if scholarsBid !== undefined && !scholarsBid.approved}
														<!-- Show preference change buttons + unbid -->
														{#if sortedLevels.length > 0}
															{@const currentLabel = sortedLevels.find(
																(l) => l.id === scholarsBid.preferenceid
															)?.label}
															{#if currentLabel !== undefined}
																<div data-testid={`bid-preference-${index}-${roleIndex}`}>
																	<em>{currentLabel}</em>
																</div>
															{/if}
														{/if}
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

<style>
	.highlight {
		background: var(--salient-color-faded);
	}
</style>
