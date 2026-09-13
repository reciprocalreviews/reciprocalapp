import { describe, expect, it } from 'vitest';
import { anyWithheld, withholdingFor } from './withheldVolunteers';

const rows = (...roleids: string[]) => roleids.map((roleid) => ({ roleid }));

describe('withholdingFor', () => {
	it('reports nothing withheld when the viewer sees every row', () => {
		const w = withholdingFor('r', rows('r', 'r'), [{ role: 'r', volunteer_count: 2 }]);
		expect(w).toEqual({ total: 2, visible: 2, withheld: 0, all: false });
	});

	it('reports the difference when some rows are hidden', () => {
		const w = withholdingFor('r', rows('r'), [{ role: 'r', volunteer_count: 5 }]);
		expect(w.withheld).toBe(4);
		expect(w.all).toBe(false);
	});

	it('flags a roster the viewer may see none of', () => {
		const w = withholdingFor('r', [], [{ role: 'r', volunteer_count: 5 }]);
		expect(w).toEqual({ total: 5, visible: 0, withheld: 5, all: true });
	});

	it('does not call an empty role a withheld one', () => {
		// total 0 and visible 0 is a role nobody has volunteered for, not a hidden
		// roster; saying "0 volunteers are not listed" would be nonsense.
		const w = withholdingFor('r', [], [{ role: 'r', volunteer_count: 0 }]);
		expect(w.all).toBe(false);
		expect(w.withheld).toBe(0);
	});

	it('counts only the role asked about', () => {
		const w = withholdingFor('r', rows('r', 'other', 'other'), [{ role: 'r', volunteer_count: 3 }]);
		expect(w.visible).toBe(1);
		expect(w.withheld).toBe(2);
	});

	it('claims nothing when the counts did not load', () => {
		// Null counts mean the RPC failed, which is not the same as "everything is
		// hidden" — falling back to the visible rows reports an honest zero.
		const w = withholdingFor('r', rows('r'), null);
		expect(w).toEqual({ total: 1, visible: 1, withheld: 0, all: false });
	});

	it('treats a role missing from the counts as uncounted rather than empty', () => {
		const w = withholdingFor('r', rows('r'), [{ role: 'other', volunteer_count: 9 }]);
		expect(w.total).toBe(1);
		expect(w.withheld).toBe(0);
	});

	it('never reports a negative withholding', () => {
		// The rows and the counts are two round trips; a volunteer can leave between
		// them, leaving the viewer holding more rows than the count admits to.
		const w = withholdingFor('r', rows('r', 'r', 'r'), [{ role: 'r', volunteer_count: 1 }]);
		expect(w.withheld).toBe(0);
	});
});

describe('anyWithheld', () => {
	it('is false when every roster is complete', () => {
		expect(
			anyWithheld(['a', 'b'], rows('a', 'b'), [
				{ role: 'a', volunteer_count: 1 },
				{ role: 'b', volunteer_count: 1 }
			])
		).toBe(false);
	});

	it('is true when any one role is withholding', () => {
		expect(
			anyWithheld(['a', 'b'], rows('a', 'b'), [
				{ role: 'a', volunteer_count: 1 },
				{ role: 'b', volunteer_count: 4 }
			])
		).toBe(true);
	});

	it('is false with no counts loaded', () => {
		expect(anyWithheld(['a'], rows('a'), null)).toBe(false);
	});
});
