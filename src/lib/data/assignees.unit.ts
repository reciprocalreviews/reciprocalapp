import { describe, expect, test } from 'vitest';
import { alreadyAssigned } from './assignees';
import type { AssignmentRow } from '$data/types';

/** Only the four fields alreadyAssigned reads; the rest of AssignmentRow is
 * irrelevant to the rule, so build rows narrowly and cast at the call. */
function assignment(submission: string, scholar: string, role: string) {
	return { submission, scholar, role } as AssignmentRow;
}

describe('alreadyAssigned', () => {
	test('finds an existing assignment for the same submission, scholar, and role', () => {
		const rows = [assignment('s1', 'alice', 'reviewer')];
		expect(alreadyAssigned(rows, 's1', 'alice', 'reviewer')).toBe(true);
	});

	test('does not match a different submission', () => {
		const rows = [assignment('s1', 'alice', 'reviewer')];
		expect(alreadyAssigned(rows, 's2', 'alice', 'reviewer')).toBe(false);
	});

	test('does not match a different scholar', () => {
		const rows = [assignment('s1', 'alice', 'reviewer')];
		expect(alreadyAssigned(rows, 's1', 'bob', 'reviewer')).toBe(false);
	});

	// The same person can hold two roles on one submission (e.g. AE and
	// reviewer), so the role has to be part of the match.
	test('does not match a different role on the same submission', () => {
		const rows = [assignment('s1', 'alice', 'reviewer')];
		expect(alreadyAssigned(rows, 's1', 'alice', 'editor')).toBe(false);
	});

	test('treats null assignments as no assignments', () => {
		expect(alreadyAssigned(null, 's1', 'alice', 'reviewer')).toBe(false);
	});
});
