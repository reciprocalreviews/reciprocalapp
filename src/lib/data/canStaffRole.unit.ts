import { describe, expect, test } from 'vitest';
import canStaffRole from './canStaffRole';
import type { RoleRow } from '#data/types.js';

/** The enforcing copy is public.can_staff_role; supabase/tests/rpc/unmatched_name_joined.sql
 * asserts the same cases against it. This side only decides what to offer, so the two must
 * agree or the UI offers an invitation the database refuses. */

function role(id: string, priority: number, approver: string | null = null): RoleRow {
	return {
		id,
		priority,
		approver,
		venueid: 'v1',
		name: id,
		description: '',
		invited: true,
		biddable: false,
		anonymous_authors: false,
		desired_assignments: 1,
		max_bids: null,
		volunteer_visibility: 'all'
	};
}

function holding(
	scholarid: string,
	roleid: string,
	active = true,
	accepted: 'accepted' | 'invited' | 'declined' = 'accepted'
) {
	return { scholarid, roleid, active, accepted };
}

const EDITOR = role('editor', 0);
const AE = role('ae', 1);
const REVIEWER = role('reviewer', 2, 'ae');
const ROLES = [EDITOR, AE, REVIEWER];

describe('canStaffRole', () => {
	test('a venue admin staffs every role', () => {
		expect(canStaffRole(EDITOR, ROLES, 'me', true, [])).toBe(true);
	});

	test('a top-role holder staffs every role, even while paused', () => {
		const mine = [holding('me', 'editor', false)];
		expect(canStaffRole(AE, ROLES, 'me', false, mine)).toBe(true);
		expect(canStaffRole(REVIEWER, ROLES, 'me', false, mine)).toBe(true);
	});

	test('the holder of a role’s approving role staffs that role and no other', () => {
		const mine = [holding('me', 'ae')];
		expect(canStaffRole(REVIEWER, ROLES, 'me', false, mine)).toBe(true);
		expect(canStaffRole(AE, ROLES, 'me', false, mine)).toBe(false);
	});

	test('a paused or unaccepted approver does not', () => {
		expect(canStaffRole(REVIEWER, ROLES, 'me', false, [holding('me', 'ae', false)])).toBe(false);
		expect(canStaffRole(REVIEWER, ROLES, 'me', false, [holding('me', 'ae', true, 'invited')])).toBe(
			false
		);
	});

	test('an ordinary volunteer, or nobody signed in, does not', () => {
		expect(canStaffRole(REVIEWER, ROLES, 'me', false, [holding('me', 'reviewer')])).toBe(false);
		expect(canStaffRole(REVIEWER, ROLES, null, false, [holding('me', 'ae')])).toBe(false);
	});
});
