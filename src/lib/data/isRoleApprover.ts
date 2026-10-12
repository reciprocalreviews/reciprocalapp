import type { RoleRow, VolunteerRow } from '$data/types';

export default function isRoleApprover(
	// The role to check
	role: Pick<RoleRow, 'approver'>,
	// The volunteers to check
	volunteers: Pick<VolunteerRow, 'scholarid' | 'roleid' | 'accepted'>[],
	// The scholar to check
	scholarID: string
): boolean {
	return volunteers.some(
		(v) => v.accepted === 'accepted' && v.scholarid === scholarID && role.approver === v.roleid
	);
}
