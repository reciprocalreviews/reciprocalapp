import { describe, expect, test } from 'vitest';
import canApproveAssignment from './canApproveAssignment';
import type { AssignmentRow, RoleRow } from '$data/types';

/** The shared table of cases. The same scenarios are asserted against the SQL
 * side in supabase/tests/rpc/atomic_crud_rpc.sql, because complete_assignment
 * re-implements this rule server-side and the two must not drift. */

const EDITOR: RoleRow = role('editor', 0, null);
const AE: RoleRow = role('ae', 1, 'editor');
const REVIEWER: RoleRow = role('reviewer', 2, 'ae');
const ROLES = [EDITOR, AE, REVIEWER];

function role(id: string, priority: number, approver: string | null): RoleRow {
	return {
		id,
		priority,
		approver,
		venueid: 'v1',
		name: id,
		description: '',
		invited: false,
		biddable: false,
		anonymous_authors: false,
		desired_assignments: 1
	} as RoleRow;
}

function assignment(
	scholar: string,
	roleID: string,
	approved: boolean,
	submission = 's1'
): AssignmentRow {
	return { submission, scholar, role: roleID, approved } as AssignmentRow;
}

describe('canApproveAssignment', () => {
	test('a venue admin can approve any role', () => {
		expect(canApproveAssignment('s1', REVIEWER, ROLES, 'me', true, [])).toBe(true);
	});

	// The admin branch short-circuits before the null guards, so it survives
	// data that has not loaded.
	test('a venue admin can approve even before assignments load', () => {
		expect(canApproveAssignment('s1', REVIEWER, null, null, true, null)).toBe(true);
	});

	test('an anonymous viewer cannot', () => {
		expect(canApproveAssignment('s1', REVIEWER, ROLES, null, false, [])).toBe(false);
	});

	test('unloaded assignments or roles deny rather than allow', () => {
		expect(canApproveAssignment('s1', REVIEWER, ROLES, 'me', false, null)).toBe(false);
		expect(canApproveAssignment('s1', REVIEWER, null, 'me', false, [])).toBe(false);
	});

	test('an unrelated scholar cannot', () => {
		expect(canApproveAssignment('s1', REVIEWER, ROLES, 'me', false, [])).toBe(false);
	});

	test('the priority-0 editor of this submission can approve any role', () => {
		const assignments = [assignment('me', 'editor', true)];
		expect(canApproveAssignment('s1', REVIEWER, ROLES, 'me', false, assignments)).toBe(true);
		expect(canApproveAssignment('s1', AE, ROLES, 'me', false, assignments)).toBe(true);
	});

	test('an editor whose own assignment is not yet approved cannot', () => {
		expect(
			canApproveAssignment('s1', REVIEWER, ROLES, 'me', false, [assignment('me', 'editor', false)])
		).toBe(false);
	});

	test('a holder of the role that approves this role can', () => {
		// REVIEWER.approver is 'ae'.
		expect(
			canApproveAssignment('s1', REVIEWER, ROLES, 'me', false, [assignment('me', 'ae', true)])
		).toBe(true);
	});

	test('a holder of some OTHER role cannot', () => {
		expect(
			canApproveAssignment('s1', REVIEWER, ROLES, 'me', false, [assignment('me', 'reviewer', true)])
		).toBe(false);
	});

	test('a role with no approver has no approver branch', () => {
		// EDITOR.approver is null, so only the priority-0 branch can grant it.
		expect(
			canApproveAssignment('s1', EDITOR, ROLES, 'me', false, [assignment('me', 'ae', true)])
		).toBe(false);
	});

	// Authority is per-submission: being the editor of a different submission
	// grants nothing here.
	test('an approved assignment on another submission does not carry over', () => {
		expect(
			canApproveAssignment('s1', REVIEWER, ROLES, 'me', false, [
				assignment('me', 'editor', true, 's2')
			])
		).toBe(false);
	});

	test("another scholar's approved assignment does not grant it to me", () => {
		expect(
			canApproveAssignment('s1', REVIEWER, ROLES, 'me', false, [
				assignment('someone', 'editor', true)
			])
		).toBe(false);
	});

	test('an assignment whose role is not in the roles list is ignored', () => {
		expect(
			canApproveAssignment('s1', REVIEWER, ROLES, 'me', false, [
				assignment('me', 'deleted-role', true)
			])
		).toBe(false);
	});
});
