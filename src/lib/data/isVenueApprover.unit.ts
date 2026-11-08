import { describe, expect, test } from 'vitest';
import isVenueApprover from './isVenueApprover';

const EDITOR = { id: 'editor', priority: 0, approver: null };
const AE = { id: 'ae', priority: 1, approver: 'editor' };
const REVIEWER = { id: 'reviewer', priority: 2, approver: 'ae' };
const ROLES = [EDITOR, AE, REVIEWER];
const VENUE = { admins: ['admin'] };

function volunteer(
	scholarid: string,
	roleid: string,
	accepted: 'accepted' | 'invited' | 'declined' = 'accepted'
) {
	return { scholarid, roleid, accepted };
}

describe('isVenueApprover', () => {
	test('a venue admin is, without volunteering', () => {
		expect(isVenueApprover(VENUE, ROLES, [], 'admin')).toBe(true);
	});

	test('an accepted editor is', () => {
		expect(isVenueApprover(VENUE, ROLES, [volunteer('me', 'editor')], 'me')).toBe(true);
	});

	test('an accepted volunteer in a role that approves another is', () => {
		expect(isVenueApprover(VENUE, ROLES, [volunteer('me', 'ae')], 'me')).toBe(true);
	});

	test('a volunteer in a role that approves nothing is not', () => {
		expect(isVenueApprover(VENUE, ROLES, [volunteer('me', 'reviewer')], 'me')).toBe(false);
	});

	test('an invitation not yet accepted does not count', () => {
		expect(isVenueApprover(VENUE, ROLES, [volunteer('me', 'ae', 'invited')], 'me')).toBe(false);
		expect(isVenueApprover(VENUE, ROLES, [volunteer('me', 'editor', 'invited')], 'me')).toBe(false);
	});

	test("someone else's volunteering does not count", () => {
		expect(isVenueApprover(VENUE, ROLES, [volunteer('other', 'ae')], 'me')).toBe(false);
	});

	test('nobody signed in is not', () => {
		expect(isVenueApprover(VENUE, ROLES, [volunteer('me', 'ae')], null)).toBe(false);
	});
});
