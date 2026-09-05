/** The submissions-list view logic: search matching, the author-visibility gate
 * that search has to honor, payment status, and the sort/filter pipeline.
 *
 * Extracted from the submissions page so the ordering and the privacy gate can
 * be tested directly. Everything here is pure — the page's reactive reads are
 * passed in as a context object, including `now`, so the done-visibility window
 * is deterministic in tests. */

/** Only the submission fields the view logic reads. */
export type ViewSubmission = {
	id: string;
	title: string;
	externalid: string;
	authors: string[];
	status: string;
	created_at: string;
	completed_at: string | null;
	transactions: string[];
};

/** Only the assignment fields the view logic reads. */
export type ViewAssignment = { submission: string; scholar: string; role: string };

export type SortColumn = 'payment' | 'title' | 'id' | 'created';

export type SubmissionsViewContext = {
	/** The signed-in scholar, or null. */
	uid: string | null;
	/** Whether that scholar administers this venue. */
	isAdmin: boolean;
	/** Assignments visible to the viewer (RLS has already filtered these). */
	assignments: ViewAssignment[] | null;
	/** Role lookup, for the anonymous_authors gate. */
	rolesById: Map<string, { anonymous_authors: boolean; priority: number }>;
	/** Which submissions already have someone in the venue's editor role, from
	 * `public.venue_submission_editors`. Not derived from `assignments`: a venue editor
	 * who is not a venue admin can see the venue's submissions and none of its
	 * assignments, so inferring it from visible rows called every submission unclaimed.
	 * Null when it hasn't loaded. */
	submissionsWithEditor: Set<string> | null;
	/** Scholar display names, ALREADY LOWERCASED, for name matching. */
	scholarName: Map<string, string>;
	/** The viewer's declared conflicts. */
	conflicts: { submissionid: string }[] | null;
	/** Transactions visible to the viewer. */
	transactions: { id: string }[] | null;
	/** The venue's done-visibility window in days, or null if the venue is unknown. */
	doneVisibilityDays: number | null;
	/** The raw search box contents; trimmed and lowercased here. */
	filter: string;
	/** When true, show only submissions still waiting for an editor. */
	needsEditorOnly: boolean;
	/** Current time in ms, injected so the visibility window is testable. */
	now: number;
	/** Sort state, in precedence order: the LAST column listed is dominant,
	 * because each pass is applied in turn over a stable sort. */
	sortOrder: SortColumn[];
	paymentSortPendingFirst: boolean;
	titleSortIncreasing: boolean;
	idSortIncreasing: boolean;
	createdSortLatestFirst: boolean;
};

/** A non-paying co-author's slot in `submission.transactions`. */
export const NULL_TRANSACTION = '00000000-0000-0000-0000-000000000000';

/** What a submission's payment column has to say.
 *
 * These used to be one number, where zero meant "nothing outstanding" — which is
 * true both of a submission whose authors paid and of one that was never charged
 * at all, and the column said "paid" for both. It was wrong for every imported
 * submission (bulk_import_submissions writes no transactions) and for every
 * submission at a payment-free venue (every author's charge is zero, so every
 * slot is a placeholder). Neither had been paid for; in the imported case the
 * tokens did not even exist yet. Splitting the states apart is what makes the
 * claim checkable. */
export type PaymentState =
	/** Transactions have not loaded, so nothing can be said. */
	| { state: 'unknown' }
	/** Nothing was ever charged for this submission. */
	| { state: 'free' }
	/** There were charges, and each has a transaction. */
	| { state: 'paid' }
	/** Charges with no visible transaction yet. */
	| { state: 'pending'; count: number };

export function submissionsView(context: SubmissionsViewContext) {
	const trimmedFilter = context.filter.trim().toLowerCase();

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
			const name = context.scholarName.get(id);
			if (name && name.includes(trimmedFilter)) return true;
		}
		return false;
	}

	/** Whether the current viewer can see the authors of a given submission,
	 * mirroring the role.anonymous_authors gate on the submission detail page.
	 * Used both by the filter (to decide whether to match author names) and by
	 * the Authors column (to decide whether to render them). */
	function canSeeAuthors(sub: ViewSubmission): boolean {
		if (context.isAdmin) return true;
		if (context.uid !== null && sub.authors.includes(context.uid)) return true;
		const viewerAssignmentsHere = context.assignments?.filter(
			(a) => a.submission === sub.id && a.scholar === context.uid
		);
		return (
			!!viewerAssignmentsHere &&
			viewerAssignmentsHere.length > 0 &&
			!viewerAssignmentsHere.some((a) => context.rolesById.get(a.role)?.anonymous_authors)
		);
	}

	/** True if the search term matches the submission's title, external ID, any
	 * visible author name, or any visible assigned-reviewer name.
	 *
	 * Reviewer-name matches honor `venue.anonymous_assignments` automatically:
	 * RLS already filters which assignment rows arrive. Author-name matches honor
	 * `role.anonymous_authors` explicitly, so a reviewer in an anonymous-authors
	 * role cannot discover author names via search. */
	function matchesFilter(sub: ViewSubmission): boolean {
		if (matches(sub.title)) return true;
		if (matches(sub.externalid)) return true;

		const subAssignments = context.assignments?.filter((a) => a.submission === sub.id) ?? [];
		if (anyScholarMatches(subAssignments.map((a) => a.scholar))) return true;

		if (canSeeAuthors(sub) && anyScholarMatches(sub.authors)) return true;

		return false;
	}

	/** What this submission's payment column should say.
	 *
	 * NullUUID slots represent non-paying co-authors — no transaction is expected
	 * for them, so they neither count toward the pending tally nor make a
	 * submission look charged. A submission with nothing expected of anyone was
	 * never charged, which is a different fact from having been paid for and is
	 * reported as its own state rather than borrowing "paid". */
	function paymentStatus(sub: ViewSubmission): PaymentState {
		if (context.transactions === null) return { state: 'unknown' };
		const expected = sub.transactions.filter((t) => t !== NULL_TRANSACTION);
		if (expected.length === 0) return { state: 'free' };
		const visible = expected
			.map((t) => context.transactions?.find((tr) => tr.id === t))
			.filter((t) => t !== undefined);
		const outstanding = expected.length - visible.length;
		return outstanding === 0 ? { state: 'paid' } : { state: 'pending', count: outstanding };
	}

	/** How many charges are outstanding, for ordering only. Free and paid tie at
	 * zero: neither is waiting on anybody, and the sort is "pending first". */
	function outstandingCharges(sub: ViewSubmission): number {
		const status = paymentStatus(sub);
		return status.state === 'pending' ? status.count : status.state === 'unknown' ? -1 : 0;
	}

	/** True if nobody is editing this submission yet.
	 *
	 * A submission with no priority-0 assignment is stalled: its author has paid, but
	 * until someone holds the editor role on it, no assignment can be approved and it
	 * cannot be marked done. `create_submission` seats the venue's editor when there is
	 * exactly one, so this is the venue with several editors, or none.
	 *
	 * Done submissions are never flagged — whoever edited them has moved on, and a
	 * finished paper is not waiting for anyone. Otherwise this is deliberately the same
	 * test `can_claim_editor_role` makes, so the flag and the claim button it carries
	 * agree with what the database will actually allow. */
	function needsEditor(sub: ViewSubmission): boolean {
		if (sub.status === 'done') return false;
		if (context.submissionsWithEditor === null) return false;
		return !context.submissionsWithEditor.has(sub.id);
	}

	/** Ascending comparators. Direction is applied by the caller rather than by
	 * reversing the array: `reverse()` after a stable sort also reverses the ties
	 * the PREVIOUS pass established, so the default newest-first list was
	 * breaking created_at ties by descending title instead of ascending. */
	const ascending: Record<SortColumn, (a: ViewSubmission, b: ViewSubmission) => number> = {
		payment: (a, b) => outstandingCharges(a) - outstandingCharges(b),
		title: (a, b) => a.title.localeCompare(b.title),
		id: (a, b) => a.externalid.localeCompare(b.externalid),
		created: (a, b) => a.created_at.localeCompare(b.created_at)
	};

	/** +1 to sort ascending, -1 to sort descending. Note `created`'s flag has the
	 * opposite polarity to the other three: it is named "latest first". */
	function direction(column: SortColumn): number {
		switch (column) {
			case 'payment':
				return context.paymentSortPendingFirst ? 1 : -1;
			case 'title':
				return context.titleSortIncreasing ? 1 : -1;
			case 'id':
				return context.idSortIncreasing ? 1 : -1;
			case 'created':
				return context.createdSortLatestFirst ? -1 : 1;
		}
	}

	/** Sort and filter submissions. Done submissions older than the venue's
	 * done_visibility_days window are hidden from the list (they remain
	 * accessible by direct link). What remains is partitioned so that done
	 * submissions always sort to the bottom regardless of the active sort. */
	function sortedAndFiltered<T extends ViewSubmission>(submissions: T[]): T[] {
		const cutoffMs =
			context.doneVisibilityDays === null
				? 0
				: context.now - context.doneVisibilityDays * 24 * 60 * 60 * 1000;
		const subs = submissions
			.filter((sub) => trimmedFilter === '' || matchesFilter(sub))
			.filter((sub) => !context.needsEditorOnly || needsEditor(sub))
			.filter(
				(sub) =>
					context.conflicts !== null && !context.conflicts.some((c) => c.submissionid === sub.id)
			)
			.filter((sub) => {
				if (sub.status !== 'done') return true;
				if (sub.completed_at === null) return true;
				return new Date(sub.completed_at).getTime() >= cutoffMs;
			});

		for (const column of context.sortOrder) {
			const compare = ascending[column];
			const sign = direction(column);
			subs.sort((a, b) => sign * compare(a, b));
		}

		// Partition: reviewing first, then done. Within each group the active
		// sort order is preserved.
		const reviewing = subs.filter((s) => s.status !== 'done');
		const finished = subs.filter((s) => s.status === 'done');
		return [...reviewing, ...finished];
	}

	return {
		matches,
		anyScholarMatches,
		canSeeAuthors,
		matchesFilter,
		paymentStatus,
		needsEditor,
		sortedAndFiltered
	};
}
