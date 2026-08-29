/** Whether a scholar may see a submission at all.
 *
 * This mirrors, branch for branch, the `"admins, authors, assigned, and bidders
 * can view submissions"` SELECT policy on `public.submissions` (declared in
 * supabase/schemas/assignments.sql, after the assignments table exists). The
 * database is the enforcing layer — RLS decides what rows arrive — and this is
 * the second layer, so the page renders a confidentiality notice rather than a
 * half-empty page if a row ever reaches a viewer it should not have.
 *
 * Keeping the branches aligned matters more than the code being short. In
 * particular branches 3 and 6 are easy to forget, and both are of the same kind:
 * they grant venue-wide reading to people with no foothold on the individual
 * submission. A scholar who has accepted ANY biddable role may read every
 * submission in the venue, because that is how they decide what to bid on; and
 * the venue's editors may read every submission because an unclaimed one has no
 * assignment to hang a permission on. Gating on "assigned" alone would lock every
 * bidder out of the page they bid from, and every editor out of the page they are
 * being asked to take.
 */

export type ViewableSubmission = { id: string; authors: string[] };

export type SubmissionViewerContext = {
	/** The signed-in scholar, or null when anonymous. */
	uid: string | null;
	/** `venues.admins` for the submission's venue. */
	venueAdmins: string[];
	/** Every role in the venue. */
	roles: { id: string; biddable: boolean; priority: number }[] | null;
	/** The VIEWER's own volunteer records in this venue. Only `accepted` matters —
	 * the policy does not test `active`, so neither may this. */
	viewerVolunteering: { roleid: string; accepted: string }[] | null;
	/** Assignments on this submission that the viewer can see. */
	assignments: { submission: string; scholar: string; role: string; approved: boolean }[] | null;
	/** True if the viewer approves the given role, i.e. is an accepted volunteer
	 * on that role's approver. Mirrors the isApprover() SQL helper, which is
	 * venue-wide rather than submission-scoped. */
	approvesRole: (roleID: string) => boolean;
};

export default function canViewSubmission(
	submission: ViewableSubmission,
	context: SubmissionViewerContext
): boolean {
	const { uid } = context;
	if (uid === null) return false;

	// 1. A venue admin sees everything in their venue.
	if (context.venueAdmins.includes(uid)) return true;

	// 2. An author sees their own submission.
	if (submission.authors.includes(uid)) return true;

	// 3. An accepted volunteer on any biddable role in the venue — a potential
	//    bidder, who has to read the submission to decide whether to bid.
	const biddableRoleIDs = new Set((context.roles ?? []).filter((r) => r.biddable).map((r) => r.id));
	if (
		(context.viewerVolunteering ?? []).some(
			(v) => v.accepted === 'accepted' && biddableRoleIDs.has(v.roleid)
		)
	)
		return true;

	// 4. An approved assignee on this submission.
	if (
		(context.assignments ?? []).some(
			(a) => a.submission === submission.id && a.scholar === uid && a.approved
		)
	)
		return true;

	// 5. Someone who approves the role of any assignment on this submission.
	if (
		(context.assignments ?? []).some(
			(a) => a.submission === submission.id && context.approvesRole(a.role)
		)
	)
		return true;

	// 6. One of the venue's editors, whether or not they are assigned here. Every
	//    branch above needs a foothold ON the submission, so without this an editor
	//    who is not also a venue admin could not see a submission nobody is editing
	//    yet — which is precisely the submission they are meant to pick up. Like
	//    branch 3, and like the isPriorityZero() helper this mirrors, only `accepted`
	//    is tested; `active` is the stricter test that governs claiming, not reading.
	const editorRoleIDs = new Set(
		(context.roles ?? []).filter((r) => r.priority === 0).map((r) => r.id)
	);
	if (
		(context.viewerVolunteering ?? []).some(
			(v) => v.accepted === 'accepted' && editorRoleIDs.has(v.roleid)
		)
	)
		return true;

	return false;
}
