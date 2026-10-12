import type { RoleRow, ScholarID, VenueRow, VolunteerRow } from '$data/types';
import isRoleApprover from './isRoleApprover';

/** Whether a scholar helps run a venue's reviewing — an admin, one of its editors (an
 * accepted volunteer in the priority-0 role), or an accepted volunteer in a role that
 * approves some other role — as opposed to a scholar who only bids there. Venue-wide,
 * unlike canApproveAssignment, which asks about one role on one submission: this is
 * for what such a person needs before any submission is in front of them, like a
 * manuscript ID or a volunteer's address.
 *
 * Which volunteer records to pass is the caller's choice: only active ones, if pausing
 * should take the affordance away, or every accepted one, if not. */
export default function isVenueApprover(
	venue: Pick<VenueRow, 'admins'> | null,
	roles: Pick<RoleRow, 'id' | 'priority' | 'approver'>[],
	volunteering: Pick<VolunteerRow, 'scholarid' | 'roleid' | 'accepted'>[],
	scholarID: ScholarID | null
): boolean {
	if (scholarID === null) return false;
	if (venue !== null && venue.admins.includes(scholarID)) return true;
	const isEditor = volunteering.some(
		(v) =>
			v.scholarid === scholarID &&
			v.accepted === 'accepted' &&
			roles.some((r) => r.id === v.roleid && r.priority === 0)
	);
	return isEditor || roles.some((role) => isRoleApprover(role, volunteering, scholarID));
}
