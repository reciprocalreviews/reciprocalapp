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
		conflicts,
		/** Venue-defined preference levels (empty if not configured) */
		preferenceLevels,
		/** Names of scholars referenced as authors or assigned reviewers, for the filter */
		scholars
	} = $derived(data);

	/** Lowercase name lookup for use in the submissions filter. */
	const scholarName = $derived(
		new Map((scholars ?? []).map((s) => [s.id, (s.name ?? '').toLowerCase()]))
	);

	/** Role lookup so we can honor `role.anonymous_authors` when deciding
	 * whether to include author names in the search blob. */
	const rolesById = $derived(new Map((roles ?? []).map((r) => [r.id, r])));

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
	let filter = $state('');
	const locale = getLocaleContext();

	/** Lowercase filter term, or '' when nothing's been typed. Cells use this
	 * to decide whether to highlight themselves. */
	const trimmedFilter = $derived(filter.trim().toLowerCase());

	/** Whether the current viewer can see the authors of a given submission,
	 * mirroring the role.anonymous_authors gate on the submission detail
	 * page. Used both by the filter (to decide whether to match author names)
	 * and by the Authors column (to decide whether to render them). */
	function canSeeAuthors(sub: SubmissionRow): boolean {
		if (isAdmin) return true;
		if (uid !== null && sub.authors.includes(uid)) return true;
		const viewerAssignmentsHere = assignments?.filter(
			(a) => a.submission === sub.id && a.scholar === uid
		);
		return (
			!!viewerAssignmentsHere &&
			viewerAssignmentsHere.length > 0 &&
			!viewerAssignmentsHere.some((a) => rolesById.get(a.role)?.anonymous_authors)
		);
	}

	/** True if the given text contains the active filter term (case-insensitive). */
	function matches(text: string | undefined | null): boolean {
		return trimmedFilter !== '' && text !== undefined && text !== null
			? text.toLowerCase().includes(trimmedFilter)
			: false;
	}

	/** True if any of the given scholar IDs has a name matching the filter. */
	function anyScholarMatches(ids: string[]): boolean {
		if (trimmedFilter === '') return false;
		for (const id of ids) {
			const name = scholarName.get(id);
			if (name && name.includes(trimmedFilter)) return true;
		}
		return false;
	}

	/** True if the search term matches the submission's title, external ID,
	 * any visible author name, or any visible assigned-reviewer name.
	 *
	 * Reviewer-name matches honor `venue.anonymous_assignments` automatically:
	 * RLS already filters which assignment rows arrive in `assignments`, so
	 * we just match against whatever is here. Author-name matches honor
	 * `role.anonymous_authors` explicitly: a reviewer in an anonymous-authors
	 * role can see the submission but should not be able to discover author
	 * names via search. */
	function matchesFilter(sub: SubmissionRow): boolean {
		if (matches(sub.title)) return true;
		if (matches(sub.externalid)) return true;

		const subAssignments = assignments?.filter((a) => a.submission === sub.id) ?? [];
		if (anyScholarMatches(subAssignments.map((a) => a.scholar))) return true;

		if (canSeeAuthors(sub) && anyScholarMatches(sub.authors)) return true;

		return false;
	}

	/** Sort and filter submissions based on the configuration. Done
	 * submissions older than the venue's done_visibility_days window are
	 * hidden from the list (they remain accessible by direct link). What
	 * remains is partitioned so that done submissions always sort to the
	 * bottom regardless of the active sort column. */
	function sortedAndFiltered(submissions: SubmissionRow[]): SubmissionRow[] {
		const cutoffMs =
			venue === null ? 0 : Date.now() - venue.done_visibility_days * 24 * 60 * 60 * 1000;
		const subs = submissions
			.filter((sub) => trimmedFilter === '' || matchesFilter(sub))
			.filter((sub) => conflicts !== null && !conflicts.some((c) => c.submissionid === sub.id))
			.filter((sub) => {
				if (sub.status !== 'done') return true;
				if (sub.completed_at === null) return true;
				return new Date(sub.completed_at).getTime() >= cutoffMs;
			});

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
					subs.sort((a, b) => a.created_at.localeCompare(b.created_at));
					if (createdSortLatestFirst) subs.reverse();
					break;
			}
		}

		// Partition: reviewing first, then done. Within each group the
		// active sort order is preserved.
		const reviewing = subs.filter((s) => s.status !== 'done');
		const finished = subs.filter((s) => s.status === 'done');
		return [...reviewing, ...finished];
	}

	function formatDate(iso: string): string {
		return new Date(iso).toLocaleDateString();
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

		<TextField
			testid="submissions-filter"
			strings={(l) => l.page.submissions.field.filter}
			bind:text={filter}
		></TextField>

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
							<td class:highlight={matches(submission.title)}>
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
							<td class:highlight={canSeeAuthors(submission) && anyScholarMatches(submission.authors)}>
								{#if canSeeAuthors(submission)}
									{#each submission.authors as authorID, i}
										{#if i > 0},
										{/if}<ScholarLink id={authorID} />
									{/each}
								{:else}
									{PrivateLabel}
								{/if}
							</td>
							<td>{submission.expertise}</td>
							<td class:highlight={matches(submission.externalid)}>{submission.externalid}</td>
							<td>{formatDate(submission.created_at)}</td>
							<td>
								{#if submission.status === 'done'}
									<Status label={(l) => l.page.submissions.status.done} />
								{:else}
									<Status good={false} label={(l) => l.page.submissions.status.reviewing} />
								{/if}
							</td>
							<!-- If we have all the information, show metadata about bidding. -->
							{#each visibleRoles as role, roleIndex}
								<!-- This cell should show all actions available for this role and submission, based on the current scholar's role. -->
								{@const roleScholarIDs =
									assignments
										?.filter((a) => a.submission === submission.id && a.role === role.id)
										.map((a) => a.scholar) ?? []}
								<td class:highlight={anyScholarMatches(roleScholarIDs)}>
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
