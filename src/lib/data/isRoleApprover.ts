import type { RoleRow, VolunteerRow } from '$data/types';

export default function isRoleApprover(
	// The role to check
	role: RoleRow,
	// The volunteers to check
	volunteers: VolunteerRow[],
	// The scholar to check
	scholarID: string
): boolean {
	return volunteers.some(
		(v) => v.accepted === 'accepted' && v.scholarid === scholarID && role.approver === v.roleid
	);
}
