import { describe, expect, test } from 'vitest';
import Loads, { atCap } from './load';

const loads = new Loads([
	{ scholar: 'busy', role: 'reviewer', count: 3 },
	{ scholar: 'busy', role: 'ae', count: 1 },
	{ scholar: 'busy', role: null, count: 2 },
	{ scholar: 'light', role: 'reviewer', count: 1 }
]);

describe('Loads', () => {
	test('counts the role, the venue’s other roles, and other venues apart', () => {
		expect(loads.of('busy', 'reviewer', 4)).toEqual({
			used: 3,
			cap: 4,
			otherRoles: 1,
			elsewhere: 2
		});
	});

	test('a scholar with no rows has no load', () => {
		expect(loads.of('free', 'reviewer', null)).toEqual({
			used: 0,
			cap: null,
			otherRoles: 0,
			elsewhere: 0
		});
	});

	test('a role the scholar holds nothing in counts only the others', () => {
		expect(loads.of('light', 'ae', 2)).toEqual({ used: 0, cap: 2, otherRoles: 1, elsewhere: 0 });
	});
});

describe('atCap', () => {
	test('reaching the cap is at it, since one more would pass it', () => {
		expect(atCap(loads.of('busy', 'reviewer', 3))).toBe(true);
		expect(atCap(loads.of('busy', 'reviewer', 2))).toBe(true);
		expect(atCap(loads.of('busy', 'reviewer', 4))).toBe(false);
	});

	test('no cap is never at it', () => {
		expect(atCap(loads.of('busy', 'reviewer', null))).toBe(false);
	});
});
