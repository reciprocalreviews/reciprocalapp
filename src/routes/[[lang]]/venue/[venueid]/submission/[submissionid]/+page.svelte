<script lang="ts">
	import type { PublicORCIDProfile, RoleID, RoleRow, ScholarID } from '$data/types';
	import { venuePath as toVenuePath } from '#lib/data/venuePath.js';
	import { venueBarName } from '#lib/data/venueBarLinks.js';
	import Button from '#lib/components/Button.svelte';
	import Checkbox from '#lib/components/Checkbox.svelte';
	import EditableText from '#lib/components/EditableText.svelte';
	import Feedback from '#lib/components/Feedback.svelte';
	import Form from '#lib/components/Form.svelte';
	import Thanks from './Thanks.svelte';
	import {
		EditLabel,
		EmptyLabel,
		ScholarLabel,
		UnknownLabel,
		VenueLabel
	} from '#lib/components/Labels.js';
	import Link from '#lib/components/Link.svelte';
	import Options from '#lib/components/Options.svelte';
	import Page from '#lib/components/Page.svelte';
	import Paragraph from '#lib/components/Paragraph.svelte';
	import Row from '#lib/components/Row.svelte';
	import ORCIDKeywords from '#lib/components/ORCIDKeywords.svelte';
	import VenueExpertise from '#lib/components/VenueExpertise.svelte';
	import ScholarField from '#lib/components/ScholarField.svelte';
	import ScholarLink from '#lib/components/ScholarLink.svelte';
	import { ScholarSearch } from '#lib/components/ScholarSearch.svelte.js';
	import Status from '#lib/components/Status.svelte';
	import Subheader from '#lib/components/Subheader.svelte';
	import Table from '#lib/components/Table.svelte';
	import TextField from '#lib/components/TextField.svelte';
	import Tip from '#lib/components/Tip.svelte';
	import Tokens from '#lib/components/Tokens.svelte';
	import VenueLink from '#lib/components/VenueLink.svelte';
	import { affiliationLine, worksStat } from '#lib/data/orcidProfileView.js';
	import canApproveAssignment from '#lib/data/canApproveAssignment.js';
	import canClaimEditor from '#lib/data/canClaimEditor.js';
	import canViewSubmission from '#lib/data/canViewSubmission.js';
	import { getDB, NullUUID } from '#lib/data/CRUD.js';
	import {
		sortAssignees as sortAssigneesBy,
		sortBids as sortBidsBy
	} from '#lib/data/sortAssignees.js';
	import Scholar from '#lib/data/Scholar.svelte.js';
	import type LocaleText from '#lib/locales/Locale.js';
	import Text from '#lib/locales/Text.svelte';
	import { validEmail, validORCID } from '#lib/validation.js';
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
		/** Whether anyone holds the venue's editor role on this submission */
		submissionHasEditor,
		/** All balances of scholars */
		balances,
		/** The current user */
		scholar,
		/** The submission types for this venue */
		submissionTypes,
		/** Names of scholars referenced by assignments, for stable sorting */
		assignmentScholars,
		/** Contact addresses of accepted assignees, shown only to approvers */
		assigneeEmails,
		/** Venue-defined preference levels, ordered by rank */
		preferenceLevels,
		/** Per-scholar count of active (approved, uncompleted) assignments in this venue */
		venueActiveCounts,
		/** Per-scholar count of active assignments on OTHER venues (RLS-gated) */
		elsewhereActiveCounts,
		/** The viewer's own accepted volunteer records in this venue */
		viewerVolunteering,
		/** Thank-you notes for this submission, filtered by RLS to the viewer */
		thanks,
		/** Assignments the import could not match to a scholar, that this viewer could approve */
		unmatched
	} = $derived(data);

	/** How this venue is addressed in links from here. Empty when the venue failed to load,
	 * which is the case the two error breadcrumbs below are for — they render a dead link
	 * rather than none so the page keeps its shape. */
	const venuePath = $derived(venue === null ? '' : toVenuePath(venue));

	function nameOf(scholarID: string): string {
		return assignmentScholars.find((s) => s.id === scholarID)?.name ?? '';
	}

	// Warm the mirror for whoever reads this page next. Never awaited, browser-only, and
	// bounded in the database: the claim stamps a cooldown before any fetch happens, so ten
	// editors opening the same submission produce one refresh between them rather than ten.
	$effect(() => {
		db().requestORCIDRefresh(assignmentScholars.map((s) => s.id));
	});

	/** The mirrored ORCID columns for one assignee, or null when RR has not read them. */
	function profileOf(scholarID: string) {
		return assignmentScholars.find((s) => s.id === scholarID)?.orcid_profiles ?? null;
	}

	/** The lookups the assignee/bid sorts need. Declared once so both call sites
	 * agree; the ordering rules themselves live in $lib/data/sortAssignees. */
	const assigneeContext = $derived({
		getBalance,
		nameOf
	});

	/** The bid whose decline form is open, and the explanation being written for it. Local
	 * state rather than anything derived from load data, so a realtime refetch mid-sentence
	 * does not wipe what the approver has typed. */
	let decliningID = $state<string | null>(null);
	let declineReason = $state('');

	function validDeclineReason(text: string) {
		const length = text.trim().length;
		return length === 0 || length > 1000
			? (l: LocaleText) => l.page.submission.field.declineReason.invalid
			: undefined;
	}

	function sortAssignees<T extends { scholar: string }>(items: T[]): T[] {
		return sortAssigneesBy(items, assigneeContext);
	}

	function sortBids<T extends { scholar: string; preferenceid: string | null }>(items: T[]): T[] {
		return sortBidsBy(items, { ...assigneeContext, preferenceLevels });
	}

	type Request = {
		bid: boolean;
		approved: boolean;
		completed: boolean;
		compensation_requested_at: string | null;
	};

	/** A compensation request with no approved assignment behind it: someone did the
	 * work on a submission nobody could seat them on, and asks an approver to pay for it. */
	function isClaim(a: Request): boolean {
		return !a.approved && !a.completed && a.compensation_requested_at !== null;
	}

	/** Something an approver is being asked to answer: a pending bid or a claim. */
	function isRequest(a: Request): boolean {
		return (a.bid && !a.approved) || isClaim(a);
	}

	function preferenceLabelFor(preferenceid: string | null): string | undefined {
		if (preferenceid === null) return undefined;
		return preferenceLevels?.find((l) => l.id === preferenceid)?.label;
	}

	function papersCapFor(scholarID: string, roleID: string): number | null {
		return (
			volunteers?.find((v) => v.scholarid === scholarID && v.roleid === roleID)?.papers ?? null
		);
	}

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

	/** Non-editor assignments that are approved but not yet compensated.
	 * These block marking the submission done, since every level of review
	 * must be evaluated and paid before completion. The editor's own
	 * priority-0 assignment is excluded: it is compensated as part of the
	 * mark-done action itself. */
	let completionBlockers = $derived(
		assignments !== null && roles !== null
			? assignments.filter((a) => {
					const role = roles.find((r) => r.id === a.role);
					return role !== undefined && role.priority > 0 && a.approved && !a.completed;
				})
			: []
	);

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

	/** Whether the current scholar holds an approved assignment on this
	 * submission. This asks whether the list has anything in it — it used to ask
	 * only whether the list EXISTED, which is true for any signed-in scholar once
	 * the page's data has loaded, so every check built on it was vacuous. */
	let isAssigned = $derived(scholarAssignments !== undefined && scholarAssignments.length > 0);

	/** Whether the current scholar may see this submission at all, mirroring the
	 * submissions SELECT policy. RLS is the enforcing layer — a row the viewer
	 * may not see never arrives — and this is the second layer, so an unexpected
	 * row produces the confidentiality notice rather than a half-rendered page. */
	let canView = $derived(
		submission !== null &&
			venue !== null &&
			canViewSubmission(submission, {
				uid: scholar?.id ?? null,
				venueAdmins: venue.admins,
				roles,
				viewerVolunteering,
				assignments,
				// Mirrors the isApprover() SQL helper: an accepted volunteer on the
				// approver OF this role, venue-wide rather than submission-scoped.
				approvesRole: (roleID) => {
					const approver = roles?.find((r) => r.id === roleID)?.approver ?? null;
					return (
						approver !== null &&
						(viewerVolunteering ?? []).some(
							(v) => v.accepted === 'accepted' && v.roleid === approver
						)
					);
				}
			})
	);

	/** The venue's editor role, if it has one. Claiming is only ever about this role —
	 * priority 0 is what the database checks when deciding who edits a submission. */
	let editorRole = $derived((roles ?? []).find((r) => r.priority === 0));

	/** Roles for which the current scholar can approve assignments on this
	 * submission, computed via the shared canApproveAssignment helper. */
	let rolesScholarCanApprove = $derived(
		submission !== null && roles !== null
			? roles.filter((r) =>
					canApproveAssignment(submission.id, r, roles, scholar?.id ?? null, isAdmin, assignments)
				)
			: []
	);

	/** Whether the scholar may answer bids here — approve or decline them in some biddable
	 * role — which is also who may open and close the submission's bidding. */
	let canAnswerBids = $derived(rolesScholarCanApprove.some((r) => r.biddable));

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
	/** Owned here rather than left inside the field, because the Add button is enabled by
	 * whether the text resolved to somebody and the duplicate check needs their id. That
	 * resolution now happens on blur, so the form can say "no scholar with that email or
	 * ORCID" while it is still the field's fault, instead of accepting the text and
	 * reporting it only after the button is pressed. */
	const newAssignmentSearch = new ScholarSearch(getDB());

	/** The mirrored record for whoever the field has just resolved to.
	 *
	 * This is the one surface where the cache is genuinely likely to be COLD: an editor can
	 * type the iD of somebody nobody on this platform has ever looked at. So unlike the
	 * table, which renders what it has and moves on, this asks and then looks again once.
	 *
	 * It deliberately does NOT gate the Add button. Assigning has to work when ORCID is
	 * unreachable, when the record is private, and when it simply has not been read yet. */
	let newAssignmentProfile = $state<PublicORCIDProfile | null>(null);

	$effect(() => {
		const id = newAssignmentSearch.id;
		newAssignmentProfile = null;
		if (id === undefined) return;

		// Cancelled on teardown and whenever the field resolves to somebody else, so a slow
		// answer cannot land in a form that has moved on -- the same discipline
		// ScholarSearch keeps with its own sequence counter.
		let live = true;
		let timer: ReturnType<typeof setTimeout> | undefined;

		const read = async () => {
			const { data } = await db().getORCIDProfile(id);
			if (!live) return;
			if (data) newAssignmentProfile = data;
			return data;
		};

		void read().then((found) => {
			if (!live || (found && found.fetch_status !== 'pending')) return;
			// Nothing cached, or a claim still in flight. Ask, then look once more rather
			// than polling: if it is still not there, the ORCID link alone is the honest
			// answer and the editor has lost nothing.
			db().requestORCIDRefresh([id]);
			timer = setTimeout(() => void read(), 2500);
		});

		return () => {
			live = false;
			clearTimeout(timer);
		};
	});
	let newAssignmentSubmitting = $state(false);
	let newAssignmentError: ((l: LocaleText) => string) | undefined = $state(undefined);

	/** Surface feedback for the mark-done action that isn't already
	 * delivered by the notification facility (e.g., insufficient tokens). */
	let completionFeedback: ((l: LocaleText) => string) | undefined = $state(undefined);

	function getVolunteer(role: RoleID, scholar: ScholarID) {
		return volunteers?.find((v) => v.roleid === role && v.scholarid === scholar);
	}

	// A map, built once, rather than a linear scan per lookup. getBalance is the
	// body of the sortAssignees/sortBids comparators, so a `.find()` here made
	// ordering a candidate list O(n^2 log n) — and on a venue whose roster is the
	// whole community, that list is the whole community. Its neighbours
	// venueActiveCounts and elsewhereActiveCounts were already built as maps; this
	// one was the exception.
	let balanceByScholar = $derived(
		new Map((balances ?? []).map((balance) => [balance.scholar, balance.count]))
	);

	/** Whether this viewer may see other scholars' balances on this page.
	 *
	 * Balances are private (#109). The audience is the people who run and staff the
	 * reviewing — those who can approve an assignment here — and the database agrees:
	 * scholar_balances returns an outsider nothing but their own row. This exists so
	 * the page does not render a column of confident zeroes for everyone else; it
	 * matches the server rather than replacing it.
	 *
	 * canViewSubmission admits authors and fellow bidders to this page, and they are
	 * deliberately NOT in the audience: seeing who reviews your manuscript is not the
	 * same as seeing what they are paid. */
	let canSeeBalances = $derived(rolesScholarCanApprove.length > 0);

	function getBalance(scholar: ScholarID) {
		// Withheld, not merely hidden. Removing the column alone would leave the ROW
		// ORDER as a balance oracle, because sortAssignees/sortBids sort ascending by
		// this value. Returning a constant makes the comparator fall through to
		// family name — which is exactly what that injection point is for.
		if (!canSeeBalances) return 0;
		return balanceByScholar.get(scholar) ?? 0;
	}
</script>

<!--
	Who a candidate is, under their name: the line an editor used to have to open
	orcid.org in another tab for. Short form, which drops the department -- it is the
	least discriminating part of an affiliation and this is the narrowest cell on the
	page. Renders nothing at all when RR has no mirror for them.
-->
{#snippet orcidContext(scholarID: string)}
	{@const profile = profileOf(scholarID)}
	{@const affiliation = affiliationLine(profile, true)}
	{@const stat = worksStat(profile)}
	{#if affiliation || stat}
		<span class="orcid-context" data-testid="assignment-orcid">
			{#if affiliation}<span class="affiliation">{affiliation}</span>{/if}
			{#if stat}<span class="works">{stat}</span>{/if}
		</span>
	{/if}
{/snippet}

<!--
	An accepted assignee's verified address, for approvers who must invite them in a
	venue's own reviewing system. Said plainly when there is none, so the editor knows
	to find another way rather than wondering whether it failed to load.
-->
<!-- Under any row whose buttons include Assign: the same reminder as above the table, in
     brief, where the approver's eye is when they click. -->
{#snippet assignNote()}
	<p class="assign-note" data-testid="assign-note">
		<Text path={(l) => l.page.submission.cell.compensationOnly} />
	</p>
{/snippet}

{#snippet assigneeEmail(scholarID: string)}
	{@const email = assigneeEmails.find((s) => s.id === scholarID)?.email ?? null}
	<span class="assignee-email" data-testid="assignee-email">
		{#if email}<a href="mailto:{email}">{email}</a>{:else}{locale().page.submission.cell
				.noEmail}{/if}
	</span>
{/snippet}

<!--
	The venue's own expertise statement first, then ORCID's keywords, marked as ORCID's.
	The order is the point: `volunteers.expertise` is what this scholar wrote FOR THIS
	VENUE about reviewing, and it is the claim a reviewing table should lead with. The
	ORCID keywords describe a research career, written for a different audience and
	possibly years ago, so they follow and say whose they are — see ORCIDKeywords for
	why the mark is on the chips rather than on a rule above them.
-->
{#snippet expertiseCell(scholarID: string, expertise: string | undefined)}
	{@const topics = profileOf(scholarID)?.keywords ?? []}
	<!-- Each side labelled by whose claim it is: the platform's own mark on what the
	     volunteer told THIS venue, ORCID's on what their public record says. Either can
	     therefore stand alone without being read as the other, which is what lets a missing
	     side simply not render rather than needing a placeholder to explain itself.
	     EmptyLabel survives for the cell with neither, where it is the honest answer. -->
	{#if expertise}<VenueExpertise>{expertise}</VenueExpertise>{/if}
	<ORCIDKeywords keywords={topics} />
	{#if !expertise && topics.length === 0}{EmptyLabel}{/if}
{/snippet}

{#snippet loadIndicator(scholarID: string, roleID: string)}
	{@const cap = papersCapFor(scholarID, roleID)}
	{@const used = venueActiveCounts?.[scholarID] ?? 0}
	{@const elsewhere = elsewhereActiveCounts?.[scholarID] ?? 0}
	{@const overCap = cap !== null && used >= cap}
	{#if cap !== null}
		<div class:over-cap={overCap} data-testid="papers-load">{used} / {cap}</div>
	{/if}
	{#if elsewhere > 0}
		<div class="elsewhere" data-testid="elsewhere-load">+{elsewhere} elsewhere</div>
	{/if}
{/snippet}

<!-- Signed out, nothing here loads: submissions are readable only by the people they involve.
     Say so rather than "does not exist", since this is usually someone following an email. -->
{#if scholar === null}
	<Page band={false} title={(l) => l.page.submission.title}>
		<Feedback text={(l) => l.page.submission.feedback.logIn}></Feedback>
	</Page>
{:else if submission === null || venue === null || roles === null || scholar === null || assignments === null || authors === null || volunteers === null || submissionTypes === null}
	<Page band={false} title={(l) => l.page.submission.title}>
		<Feedback error text={(l) => l.page.submission.feedback.notLoaded}></Feedback>
	</Page>
{:else if !canView}
	<Page band={false} title={(l) => l.page.submission.title}>
		<Feedback error text={(l) => l.page.submission.feedback.confidential}></Feedback>
	</Page>
{:else}
	<Page
		band={false}
		title={submission.title}
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
				<Link to="/venue/{venuePath}/submission/{previous.id}">{previous.externalid}</Link>→
			{/if}
			{submission.externalid}
			{#if done}
				<Status good={false} label={(l) => l.page.submission.status.done} />
			{:else}
				<Status label={(l) => l.page.submission.status.reviewing} />
				{#if submission.bidding_closed}
					<Status
						neutral
						label={(l) => l.page.submission.status.biddingClosed}
						testid="submission-bidding-closed-status"
					/>
				{/if}
			{/if}
		{/snippet}

		<!-- Only editors (priority-0) see the mark-done flow. The button
		     compensates every editor on this submission and flips the
		     status to done in one atomic action; reopening is forbidden.
		     The button is inactive until every non-editor assignment is
		     compensated, with an explanation of what's left. -->
		<!-- Anyone who may answer bids here may open or close bidding. Unchecking closes it
		     while the submission stays under review, e.g. when every seat has a reviewer but
		     some haven't registered yet. Bidders then no longer see the submission at all. -->
		{#if canAnswerBids && !done}
			<Checkbox
				on={!submission.bidding_closed}
				change={(on) => db().updateSubmissionBiddingClosed(submission.id, !on)}
				label={(l) => l.page.submission.checkbox.openForBidding}
				testid="submission-open-for-bidding"
			/>
		{/if}

		{#if isEditor && !done}
			{#if completionBlockers.length > 0}
				<Feedback
					text={(l) =>
						l.page.submission.feedback.completionBlocked.replace(
							'{count}',
							completionBlockers.length.toString()
						)}
				/>
				<ul class="blockers">
					{#each completionBlockers as blocker}
						{@const role = roles.find((r) => r.id === blocker.role)}
						<li>
							<strong>{role?.name ?? '?'}</strong>: <ScholarLink id={blocker.scholar} />
						</li>
					{/each}
				</ul>
			{/if}
			<Button
				strings={(l) => l.page.submission.button.markDone}
				testid="mark-submission-done"
				active={completionBlockers.length === 0}
				action={async () => {
					const outcome = await handle(db().markSubmissionDone(submission.id));
					if (
						typeof outcome === 'object' &&
						outcome !== null &&
						'status' in outcome &&
						outcome.status === 'insufficient'
					) {
						completionFeedback = (l) => l.page.submission.feedback.completionInsufficient;
					} else {
						completionFeedback = undefined;
					}
				}}
			/>
			{#if completionFeedback}
				<Feedback error text={completionFeedback} />
			{/if}
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
							{:else if transaction.status === 'declined'}
								{locale().page.submission.cell.declinedToPay}
							{/if}
							<Tokens amount={payment} />
						{/if}
					{/if}
				{:else}
					<!-- The same lock the submissions list uses, so both views mark a withheld
					     author the same way. The word stays: there is room for it here, and a
					     bare glyph would otherwise be the only signal. -->
					<em>{UnknownLabel} {locale().page.submission.cell.anonymized}</em>
				{/if}
			</Row>
		{:else}
			<Feedback error text={(l) => l.page.submission.feedback.noAuthors} />
		{/each}

		<Subheader icon={VenueLabel} text={(l) => l.page.submission.header.venue}></Subheader>
		<VenueLink id={venue.id} name={venue.title} slug={venue.slug} />

		<Subheader icon={EditLabel} text={(l) => l.page.submission.header.expertise}></Subheader>
		<!-- Editors as well as authors, because an imported submission has no authors
		     at all and this was therefore editable by nobody — while expertise is
		     exactly what reviewers read when deciding what to bid on. Not admins:
		     the update policy admits the seated priority-0 editor and the authors,
		     so offering an admin the control would show them one the database
		     refuses. -->
		{#if isAuthor || isEditor}
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

		<!-- Assigning here only records the work for compensation. Approvers kept assuming it
		     was the whole job, so whoever can assign here is reminded, above every control that
		     does it, to assign the person in the venue's own reviewing system too. -->
		{#if rolesScholarCanApprove.length > 0 && venue !== null}
			<Feedback
				testid="compensation-only"
				text={(l) =>
					venue.review_system_url
						? l.page.submission.feedback.compensationOnlyLinked
						: l.page.submission.feedback.compensationOnly}
				inputs={{ venue: venueBarName(venue), system: venue.review_system_url ?? '' }}
			/>
		{/if}

		<!-- People the import named who have not joined yet, in one notice. They are matched
		     from the venue's unmatched assignments page once each person joins. -->
		{#if unmatched.length > 0}
			<Feedback
				testid="unmatched-on-submission"
				text={(l) =>
					l.page.submission.feedback.unmatched
						.replaceAll(
							'{list}',
							unmatched
								.map((u) => `**${u.name}** (${roles.find((r) => r.id === u.role)?.name ?? ''})`)
								.join(', ')
						)
						.replaceAll('{venue}', venuePath)}
			/>
		{/if}

		<!-- Nobody is editing this submission yet, and this viewer is one of the venue's
		     editors, so offer to take it. Until someone does, only venue admins can approve
		     work on it and it cannot be marked done — and before can_claim_editor_role only a
		     venue admin could seat the first editor. -->
		{#if editorRole && canClaimEditor(editorRole, scholar?.id ?? null, viewerVolunteering, submissionHasEditor)}
			<Feedback text={(l) => l.page.submission.feedback.needsEditor} />
			<Button
				testid="claim-editor"
				strings={(l) => l.page.submission.button.claimEditor}
				action={() =>
					handle(db().createAssignment(submission.id, scholar!.id, editorRole.id, false, true))}
			/>
		{/if}

		<!-- If the authenticated scholar can approve any role on this submission, permit them to create new assignments. -->
		{#if rolesScholarCanApprove.length > 0}
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
				<ScholarField
					bind:text={newAssignmentScholar}
					search={newAssignmentSearch}
					strings={(l) => l.page.submission.field.newAssignment}
					testid="new-assignment-scholar"
					valid={(emailOrORCID) =>
						emailOrORCID.length > 0 && !validEmail(emailOrORCID) && !validORCID(emailOrORCID)
							? (l) => l.page.submission.field.newAssignment.invalid
							: undefined}
				/>
				<!--
					Who you just named, before you commit to assigning them. The field itself
					already resolves to a ScholarLink; this adds the part an editor previously
					had to open orcid.org for. Absent silently when RR has nothing.
				-->
				{#if newAssignmentSearch.id !== undefined}
					{@const affiliation = affiliationLine(newAssignmentProfile)}
					{@const stat = worksStat(newAssignmentProfile)}
					{@const topics = newAssignmentProfile?.keywords ?? []}
					{#if affiliation || stat || topics.length > 0}
						<div class="assignment-orcid" data-testid="new-assignment-orcid">
							{#if affiliation}<span>{affiliation}</span>{/if}
							{#if stat}<span class="works">{stat}</span>{/if}
							<ORCIDKeywords keywords={topics} />
						</div>
					{/if}
				{/if}
				<Button
					testid="new-assignment"
					strings={(l) => l.page.submission.button.createAssignment}
					active={!newAssignmentSubmitting &&
						newAssignmentRole !== undefined &&
						newAssignmentSearch.id !== undefined}
					action={async () => {
						newAssignmentSubmitting = true;
						const role = roles.find((role) => role.id === newAssignmentRole);

						// Already resolved, on blur. The button cannot be pressed until it is,
						// so this is a narrowing rather than a lookup.
						const scholarID = newAssignmentSearch.id;

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
							db().createAssignment(
								submission.id,
								scholarID,
								role.id,
								false,
								true,
								null,
								scholar?.id ?? null
							)
						).then(() => {
							newAssignmentRole = undefined;
							newAssignmentScholar = '';
							// Otherwise the field clears but stays resolved to the scholar just
							// added, leaving the Add button live over an empty box.
							newAssignmentSearch.reset();
							newAssignmentError = undefined;
							newAssignmentSubmitting = false;
						});
					}}>+ assignee</Button
				>
				{#if newAssignmentSearch.notFound}
					<!-- ScholarMatches shows "no matches" only for an empty NAME search; a
					     well-formed iD or address that matches nobody renders as nothing at
					     all there, which reads as though the field accepted it. -->
					<Feedback error text={(l) => l.page.submission.feedback.scholarNotFound} />
				{:else if newAssignmentError !== undefined}<Feedback error text={newAssignmentError} />{/if}
			</Form>
		{/if}

		<Table full>
			{#snippet header()}
				<th>{locale().page.submission.headers.role}</th>
				<th>{locale().page.submission.headers.scholar}</th>
				<th>{locale().page.submission.headers.expertise}</th>
				{#if canSeeBalances}<th>{locale().page.submission.headers.balance}</th>{/if}
				<th>{locale().page.submission.headers.load}</th>
				<th>{locale().page.submission.headers.action}</th>
			{/snippet}

			<!-- Sort roles by priority -->
			{#each roles.toSorted((a, b) => a.priority - b.priority) as role}
				<!-- An assignment is "assigned" if it's anything other than a pending bid or
				     claim: directly admin-assigned (bid=false), or a bid that's been approved
				     (bid=true, approved=true). Approving a bid only flips `approved`;
				     `bid` stays true, so we can't filter on `!bid` alone. -->
				{@const assigned = sortAssignees(
					assignments.filter((a) => role.id === a.role && !isRequest(a))
				)}
				<!-- Pending bids and claims match this role and are neither approved nor declined.
				     A claim is a compensation request with no approved assignment behind it, filed
				     on a submission nobody could seat its claimant on. Declined ones are listed
				     apart: they have been answered, so they are not asking for anything, but an
				     approver may still change their mind. -->
				{@const bidded = sortBids(
					assignments.filter((a) => role.id === a.role && isRequest(a) && a.declined_at === null)
				)}
				{@const declined = assignments.filter(
					(a) => role.id === a.role && isRequest(a) && a.declined_at !== null
				)}
				{@const isApprover = canApproveAssignment(
					submission.id,
					role,
					roles,
					scholar?.id ?? null,
					isAdmin,
					assignments
				)}
				{#each assigned as assignment}
					{@const volunteer = getVolunteer(role.id, assignment.scholar)}
					{@const cap = papersCapFor(assignment.scholar, role.id)}
					{@const used = venueActiveCounts?.[assignment.scholar] ?? 0}
					{@const overCap = cap !== null && used >= cap}
					<tr>
						<td>{role.name}</td>
						<td class={!assignment.approved ? 'unapproved' : undefined}>
							<div class="scholar-cell">
								{#if assignment.scholar === scholar.id}{locale().page.submission.cell
										.you}{:else}<ScholarLink id={assignment.scholar} />{/if}
								{#if assignment.completed}
									<Status
										testid="assignment-completed"
										label={(l) => l.page.submission.status.completed}
									/>
								{:else if assignment.approved}
									<Status label={(l) => l.page.submission.status.assigned} />
								{:else}
									<Status good={false} label={(l) => l.page.submission.status.unassigned} />
								{/if}
								{#if isApprover && assignment.approved && assignment.scholar !== scholar.id}
									{@render assigneeEmail(assignment.scholar)}
								{/if}
								{@render orcidContext(assignment.scholar)}
							</div>
						</td>
						<td>{@render expertiseCell(assignment.scholar, volunteer?.expertise)}</td>
						{#if canSeeBalances}<td><Tokens amount={getBalance(assignment.scholar)} /></td>{/if}
						<td>{@render loadIndicator(assignment.scholar, role.id)}</td>
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
													testid="complete-assignment"
													action={() => handle(db().completeAssignment(assignment.id, scholar.id))}
												/>
											{/if}
										{:else}
											<Button
												strings={overCap
													? (l) => l.page.submission.button.approveAnyway
													: (l) => l.page.submission.button.approve}
												action={() =>
													handle(db().approveAssignment(assignment, true, role, scholar.id))}
											/>
										{/if}
									{/if}
								{:else}
									{EmptyLabel}
								{/if}
							</Row>
							{#if isApprover && !assignment.completed && !assignment.approved}
								{@render assignNote()}
							{/if}
						</td>
					</tr>
				{:else}
					{#if bidded.length === 0 && (declined.length === 0 || !isApprover)}
						<tr><td>{role.name}</td><td colspan="5">{EmptyLabel}</td></tr>
					{/if}
				{/each}

				<!-- Is the current scholar an approver of this role? The bids so they can be approved. -->
				{#if bidded.length > 0 && isApprover}
					{#each bidded as assignment}
						{@const volunteer = getVolunteer(role.id, assignment.scholar)}
						{@const bidLabel = preferenceLabelFor(assignment.preferenceid)}
						{@const cap = papersCapFor(assignment.scholar, role.id)}
						{@const used = venueActiveCounts?.[assignment.scholar] ?? 0}
						{@const overCap = cap !== null && used >= cap}
						<tr>
							<td>{role.name}</td>
							<td>
								<div class="scholar-cell">
									<ScholarLink id={assignment.scholar} />
									{#if isClaim(assignment)}
										<Status
											good={false}
											testid="claim"
											label={(l) => l.page.submission.status.claim}
										/>
									{:else}
										<Status good={false} label={(l) => l.page.submission.status.bidder} />
									{/if}
									{#if bidLabel !== undefined}
										<em data-testid="bid-preference-label">{bidLabel}</em>
									{/if}
									{@render orcidContext(assignment.scholar)}
								</div>
							</td>
							<td>{@render expertiseCell(assignment.scholar, volunteer?.expertise)}</td>
							{#if canSeeBalances}<td><Tokens amount={getBalance(assignment.scholar)} /></td>{/if}
							<td>{@render loadIndicator(assignment.scholar, role.id)}</td>
							<td>
								<Row>
									{#if isClaim(assignment)}
										<!-- The claimant says the work is done, so approving and paying
										     are one decision. -->
										<Button
											testid="pay-claim"
											strings={(l) => l.page.submission.button.payClaim}
											action={() => handle(db().completeAssignment(assignment.id, scholar.id))}
										/>
										<Button
											testid="decline-bid"
											strings={(l) => l.page.submission.button.declineClaim}
											active={decliningID !== assignment.id}
											action={() => {
												decliningID = assignment.id;
												declineReason = '';
												return undefined;
											}}
										/>
									{:else if assignment.bid}
										<Button
											strings={overCap
												? (l) => l.page.submission.button.approveAnyway
												: (l) => l.page.submission.button.approveBid}
											action={() => {
												if (!scholar) return null;
												return handle(db().approveAssignment(assignment, true, role, scholar.id));
											}}
										/>
										<Button
											testid="decline-bid"
											strings={(l) => l.page.submission.button.declineBid}
											active={decliningID !== assignment.id}
											action={() => {
												decliningID = assignment.id;
												declineReason = '';
												return undefined;
											}}
										/>
									{/if}
								</Row>
								{#if !isClaim(assignment) && assignment.bid}
									{@render assignNote()}
								{/if}
							</td>
						</tr>
						{#if decliningID === assignment.id}
							<tr>
								<td colspan={canSeeBalances ? 6 : 5}>
									<Form>
										<Paragraph
											text={(l) =>
												isClaim(assignment)
													? l.page.submission.declineClaimPrompt
													: l.page.submission.declineBidPrompt}
										/>
										<!-- Forms align their children to the start, which shrinks a field to
										     its content; an explanation needs room, so this one spans the form. -->
										<div class="decline-reason-field">
											<TextField
												bind:text={declineReason}
												strings={(l) => l.page.submission.field.declineReason}
												testid="decline-bid-reason"
												inline={false}
												stretch
												valid={validDeclineReason}
											></TextField>
										</div>
										<Button
											testid="decline-bid-confirm"
											strings={(l) =>
												isClaim(assignment)
													? l.page.submission.button.confirmDeclineClaim
													: l.page.submission.button.confirmDecline}
											active={validDeclineReason(declineReason) === undefined}
											action={async () => {
												const result = await handle(
													db().declineBid(assignment, declineReason, role, scholar.id)
												);
												if (result !== false) {
													decliningID = null;
													declineReason = '';
												}
											}}
										/>
									</Form>
								</td>
							</tr>
						{/if}
					{/each}
				{/if}

				<!-- Declined bids, for approvers: who declined and why, so a second approver does
				     not answer the same bid again, and a way to assign the bidder after all. -->
				{#if declined.length > 0 && isApprover}
					{#each declined as assignment}
						{@const volunteer = getVolunteer(role.id, assignment.scholar)}
						<tr class="declined" data-testid="declined-bid">
							<td>{role.name}</td>
							<td class="unapproved">
								<div class="scholar-cell">
									<ScholarLink id={assignment.scholar} />
									<Status good={false} label={(l) => l.page.submission.status.declined} />
								</div>
							</td>
							<td>{@render expertiseCell(assignment.scholar, volunteer?.expertise)}</td>
							{#if canSeeBalances}<td><Tokens amount={getBalance(assignment.scholar)} /></td>{/if}
							<td>{@render loadIndicator(assignment.scholar, role.id)}</td>
							<td>
								<Row>
									{#if isClaim(assignment)}
										<!-- The claimant said the work is done, so changing one's mind means
										     paying for it, not just assigning them. -->
										<Button
											testid="pay-declined-claim"
											strings={(l) => l.page.submission.button.approveDeclinedClaim}
											action={() => handle(db().completeAssignment(assignment.id, scholar.id))}
										/>
									{:else}
										<Button
											testid="approve-declined-bid"
											strings={(l) => l.page.submission.button.approveDeclined}
											action={() =>
												handle(db().approveAssignment(assignment, true, role, scholar.id))}
										/>
									{/if}
								</Row>
								{#if !isClaim(assignment)}
									{@render assignNote()}
								{/if}
							</td>
						</tr>
						<!-- The reason gets a row of its own, spanning the table, so a long
						     explanation doesn't widen the Scholar column and reflow every row. -->
						<tr class="declined-reason-row" data-testid="declined-bid-reason">
							<td></td>
							<td colspan={canSeeBalances ? 5 : 4}>
								<div class="decline-explanation">
									{#if assignment.declined_by !== null}
										<span class="declined-by">
											{locale().page.submission.cell.declinedBy}
											<ScholarLink id={assignment.declined_by} />
										</span>
									{/if}
									<blockquote class="decline-reason">{assignment.decline_reason}</blockquote>
								</div>
							</td>
						</tr>
					{/each}
				{/if}
			{/each}
		</Table>

		<!-- Author thanks to reviewers (#22). Encapsulated in its own component so
		     the page stays lean; it renders the author / vetter / recipient views
		     off the RLS-filtered thanks list. -->
		<Thanks
			{submission}
			{thanks}
			scholarID={scholar.id}
			{isAuthor}
			{isAssigned}
			isVetter={isAdmin || (isEditor ?? false)}
			{done}
		/>
	</Page>
{/if}

<style>
	.unapproved {
		font-style: italic;
	}

	.decline-reason-field {
		width: 100%;
	}

	.decline-explanation {
		display: flex;
		flex-direction: column;
		gap: var(--spacing-half);
		max-width: 65ch;
	}

	/* The reason row belongs to the declined row above it, so it takes that row's stripe
	   rather than its own, and drops the gap between them. The pair is always two rows,
	   so the striping of every row after it is unchanged. */
	tr.declined:nth-child(even) + tr.declined-reason-row {
		background: var(--alternating-color);
	}

	tr.declined:nth-child(odd) + tr.declined-reason-row {
		background: none;
	}

	tr.declined-reason-row td {
		padding-top: 0;
	}

	.declined-by {
		font-size: var(--small-font-size);
		color: var(--inactive-color);
	}

	.decline-reason {
		margin: 0;
		padding-inline-start: var(--spacing);
		border-inline-start: 3px solid var(--inactive-color);
		font-size: var(--small-font-size);
	}

	.assignment-orcid {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: var(--spacing-half);
		font-size: var(--small-font-size);
		color: var(--inactive-color);
	}

	.assignee-email {
		font-size: var(--small-font-size);
		color: var(--inactive-color);
	}

	.assign-note {
		margin: var(--spacing-half) 0 0 0;
		max-width: 22ch;
		font-size: var(--small-font-size);
		color: var(--inactive-color);
	}

	.orcid-context {
		display: flex;
		flex-direction: column;
		font-size: var(--small-font-size);
		color: var(--inactive-color);
	}

	.scholar-cell {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: var(--spacing-half);
	}

	.blockers {
		margin-block: var(--spacing-half);
		padding-inline-start: var(--spacing);
	}

	.over-cap {
		color: var(--error-color);
		font-weight: bold;
	}

	.elsewhere {
		font-size: var(--extra-small-font-size);
		color: var(--inactive-color);
	}
</style>
