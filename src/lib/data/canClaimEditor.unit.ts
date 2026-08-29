import { describe, expect, test } from 'vitest';
import canClaimEditor from './canClaimEditor';
import type { RoleRow, VolunteerRow } from '$data/types';

/** The mirror of these cases lives in supabase/tests/rpc/editor_on_submission.sql, which
 * asserts them against the enforcing copy (public.can_claim_editor_role and the
 * assignments INSERT policy). This side only decides whether to offer the button, so the
 * two must agree or the UI will offer a claim the database refuses. */

const EDITOR: RoleRow = role('editor', 0);
const AE: RoleRow = role('ae', 1);

function role(id: string, priority: number): RoleRow {
	return {
		id,
		priority,
		approver: null,
		venueid: 'v1',
		name: id,
		description: '',
		invited: false,
		biddable: false,
		anonymous_authors: false,
		desired_assignments: 1
	} as RoleRow;
}

function volunteer(
	scholarid: string,
	roleid: string,
	active = true,
	accepted: 'accepted' | 'invited' | 'declined' = 'accepted'
): VolunteerRow {
	return { scholarid, roleid, active, accepted } as VolunteerRow;
}

const MINE = [volunteer('me', 'editor')];

describe('canClaimEditor', () => {
	test('an accepted editor can claim a submission nobody is editing', () => {
		expect(canClaimEditor(EDITOR, 'me', MINE, false)).toBe(true);
	});

	test('an anonymous viewer cannot', () => {
		expect(canClaimEditor(EDITOR, null, MINE, false)).toBe(false);
	});

	// There is no admin short-circuit here, unlike canApproveAssignment: being a venue
	// admin is not what this rule is about, and an admin already has a route in through
	// the ordinary assignment form.
	test('unloaded data denies rather than allows', () => {
		expect(canClaimEditor(EDITOR, 'me', null, false)).toBe(false);
		expect(canClaimEditor(EDITOR, 'me', MINE, undefined)).toBe(false);
	});

	test('a scholar who does not volunteer for the editor role cannot', () => {
		expect(canClaimEditor(EDITOR, 'me', [volunteer('someone', 'editor')], false)).toBe(false);
	});

	// `active` false is an unvolunteered role kept on file for the welcome-grant count,
	// and `invited` is an unanswered invitation. Neither is someone taking work on.
	test('an inactive or merely invited volunteer cannot', () => {
		expect(canClaimEditor(EDITOR, 'me', [volunteer('me', 'editor', false)], false)).toBe(false);
		expect(canClaimEditor(EDITOR, 'me', [volunteer('me', 'editor', true, 'invited')], false)).toBe(
			false
		);
	});

	test('the rule does not extend to non-editor roles', () => {
		expect(canClaimEditor(AE, 'me', [volunteer('me', 'ae')], false)).toBe(false);
	});

	// The whole point of the emptiness test: a second editor on the submission is a second
	// editor fee when it is marked done.
	test('nobody can claim a submission that already has an editor', () => {
		expect(canClaimEditor(EDITOR, 'me', MINE, true)).toBe(false);
	});
});
