import type { AssignmentRow, RoleID, ScholarID, SubmissionID } from '$data/types';

/** Whether the given scholar already holds an assignment in this role on this
 * submission. Shared by the submission detail form and the submissions-list
 * batch assigner so both refuse a duplicate the same way — the database has no
 * uniqueness constraint here, so a second assignment would silently appear as a
 * second row for the same person. */
export function alreadyAssigned(
	assignments: AssignmentRow[] | null,
	submission: SubmissionID,
	scholar: ScholarID,
	role: RoleID
): boolean {
	return (assignments ?? []).some(
		(a) => a.submission === submission && a.scholar === scholar && a.role === role
	);
}
