import type { RoleRow, ScholarID, VolunteerRow } from '#data/types.js';

/** The fields of a volunteer record this rule reads, so both full volunteer rows and the
 * venue commitments the unmatched page loads can be passed. */
type Holding = Pick<VolunteerRow, 'roleid' | 'scholarid' | 'active' | 'accepted'>;

/** Whether this scholar may put someone else in this role, by invitation or directly.
 *
 * Mirrors `public.can_staff_role`, the enforcing copy that create_volunteer and
 * add_to_role_and_match call. Keep the two in step: this one only decides what to offer,
 * and offering something the database refuses is the failure mode.
 *
 * True for any of:
 *
 * 1. A venue admin (`isAdmin`, which the caller already knows).
 * 2. An accepted holder of the venue's priority-0 role, who oversees every role. Paused
 *    still counts, as in public.isPriorityZero: this is about authority, not availability.
 * 3. An accepted, active holder of the role's approving role, such as an Associate Editor
 *    for Reviewer.
 */
export default function canStaffRole(
	role: RoleRow,
	roles: RoleRow[],
	scholarID: ScholarID | null | undefined,
	isAdmin: boolean,
	holdings: Holding[]
): boolean {
	if (isAdmin) return true;
	if (scholarID === null || scholarID === undefined) return false;

	const holds = (roleID: string, mustBeActive: boolean) =>
		holdings.some(
			(h) =>
				h.roleid === roleID &&
				h.scholarid === scholarID &&
				h.accepted === 'accepted' &&
				(!mustBeActive || h.active)
		);

	if (roles.some((r) => r.venueid === role.venueid && r.priority === 0 && holds(r.id, false)))
		return true;
	return role.approver !== null && holds(role.approver, true);
}
