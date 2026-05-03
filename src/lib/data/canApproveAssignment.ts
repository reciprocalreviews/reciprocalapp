import type { AssignmentRow, RoleRow, ScholarID, SubmissionID } from '$data/types';

/** Single source of truth for whether a scholar can approve assignments for
 * a given role on a given submission. The same gate applies on the
 * submissions list page, the submission detail page, and anywhere else this
 * permission needs to be checked.
 *
 * Returns true when any of the following hold:
 *
 * 1. The scholar is a venue admin.
 * 2. The scholar holds an approved assignment on this submission for the
 *    venue's highest-priority role (priority 0 — the "editor" of the
 *    submission). Editors can approve assignments for any role on
 *    submissions they edit.
 * 3. The scholar holds an approved assignment on this submission for the
 *    role that approves the given role (i.e., role.approver).
 */
export default function canApproveAssignment(
	submissionID: SubmissionID,
	role: RoleRow,
	roles: RoleRow[] | null,
	scholarID: ScholarID | null,
	isAdmin: boolean,
	assignments: AssignmentRow[] | null
): boolean {
	if (isAdmin) return true;
	if (scholarID === null || assignments === null || roles === null) return false;

	const myApprovedHere = assignments.filter(
		(a) => a.submission === submissionID && a.scholar === scholarID && a.approved
	);

	// Editor of this submission can approve any role.
	if (myApprovedHere.some((a) => roles.some((r) => r.id === a.role && r.priority === 0)))
		return true;

	// Assigned to the role that approves this role.
	if (role.approver !== null && myApprovedHere.some((a) => a.role === role.approver)) return true;

	return false;
}
