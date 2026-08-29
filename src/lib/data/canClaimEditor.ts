import type { RoleRow, ScholarID, VolunteerRow } from '$data/types';

/** Whether this scholar may take on a submission nobody is editing yet.
 *
 * A third rule alongside `canApproveAssignment` and `isRoleApprover`, and deliberately
 * separate from both: those answer "may I approve this for someone else?", while this one
 * answers "may I take this?". Folding it into `canApproveAssignment` would widen a rule
 * that governs approving anyone into one that also governs seating yourself.
 *
 * Mirrors `public.can_claim_editor_role` — the enforcing copy, which is what the
 * assignments INSERT policy calls. Keep the two in step: this one only decides whether to
 * offer the button, and offering one the database refuses is the failure mode.
 *
 * `hasEditor` is passed in rather than derived from assignment rows, because the caller
 * usually cannot see them: a venue editor who is not a venue admin sees the venue's
 * submissions and none of its assignments, so inferring "unclaimed" from what they can see
 * would call every submission unclaimed. It comes from `public.submission_has_editor`,
 * which answers exactly that question without naming anyone.
 *
 * True when all of these hold:
 *
 * 1. The role is the venue's priority-0 role — the one whose holders act as editors.
 * 2. The scholar is an active, accepted volunteer on it.
 * 3. Nobody holds that role on the submission yet. An editor already has it; a second one
 *    would mean a second editor fee when it is marked done.
 */
export default function canClaimEditor(
	role: RoleRow,
	scholarID: ScholarID | null,
	volunteering: VolunteerRow[] | null,
	hasEditor: boolean | undefined
): boolean {
	if (scholarID === null || volunteering === null || hasEditor === undefined) return false;
	if (role.priority !== 0) return false;
	if (hasEditor) return false;

	return volunteering.some(
		(v) =>
			v.roleid === role.id && v.scholarid === scholarID && v.active && v.accepted === 'accepted'
	);
}
