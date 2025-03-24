import type { RoleRow, VolunteerRow } from '$data/types';

export default function isRoleApprover(
	role: RoleRow,
	volunteers: VolunteerRow[],
	uid: string
): boolean {
	return volunteers.some(
		(v) => v.accepted === 'accepted' && v.scholarid === uid && role.approver === v.roleid
	);
}
