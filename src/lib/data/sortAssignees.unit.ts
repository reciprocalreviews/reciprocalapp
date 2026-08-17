import { describe, expect, test } from 'vitest';
import { sortAssignees, sortBids, type AssigneeContext } from './sortAssignees';

const NAMES: Record<string, string> = {
	alice: 'Alice Adams',
	bob: 'Bob Baker',
	cara: 'Cara Clark',
	dan: 'Dan Adams'
};

function context(balances: Record<string, number>): AssigneeContext {
	return {
		getBalance: (id) => balances[id] ?? 0,
		nameOf: (id) => NAMES[id] ?? ''
	};
}

const ids = <T extends { scholar: string }>(rows: T[]) => rows.map((r) => r.scholar);

describe('sortAssignees', () => {
	// Lowest balance first: the undercompensated are the ones most in need of
	// paid work (DESIGN.md #93).
	test('orders by balance, neediest first', () => {
		const rows = [{ scholar: 'alice' }, { scholar: 'bob' }, { scholar: 'cara' }];
		expect(ids(sortAssignees(rows, context({ alice: 1, bob: 9, cara: 5 })))).toEqual([
			'alice',
			'cara',
			'bob'
		]);
	});

	test('breaks a balance tie by family name, ascending', () => {
		const rows = [{ scholar: 'cara' }, { scholar: 'bob' }, { scholar: 'alice' }];
		expect(ids(sortAssignees(rows, context({ alice: 5, bob: 5, cara: 5 })))).toEqual([
			'alice',
			'bob',
			'cara'
		]);
	});

	test('sorts by family name, not given name', () => {
		// "Dan Adams" precedes "Bob Baker" on Adams < Baker.
		const rows = [{ scholar: 'bob' }, { scholar: 'dan' }];
		expect(ids(sortAssignees(rows, context({ bob: 1, dan: 1 })))).toEqual(['dan', 'bob']);
	});

	test('treats an unknown scholar as balance 0 and no name', () => {
		const rows = [{ scholar: 'ghost' }, { scholar: 'alice' }];
		expect(ids(sortAssignees(rows, context({ alice: 2 })))).toEqual(['ghost', 'alice']);
	});

	test('does not mutate the input', () => {
		const rows = [{ scholar: 'alice' }, { scholar: 'bob' }];
		sortAssignees(rows, context({ alice: 1, bob: 9 }));
		expect(ids(rows)).toEqual(['alice', 'bob']);
	});
});

const LEVELS = [
	{ id: 'first', rank: 1 },
	{ id: 'second', rank: 2 },
	{ id: 'third', rank: 3 }
];

describe('sortBids', () => {
	test('orders by preference rank, most preferred first', () => {
		const rows = [
			{ scholar: 'alice', preferenceid: 'third' },
			{ scholar: 'bob', preferenceid: 'first' },
			{ scholar: 'cara', preferenceid: 'second' }
		];
		expect(ids(sortBids(rows, { ...context({}), preferenceLevels: LEVELS }))).toEqual([
			'bob',
			'cara',
			'alice'
		]);
	});

	test('sorts an unset preference last', () => {
		const rows = [
			{ scholar: 'alice', preferenceid: null },
			{ scholar: 'bob', preferenceid: 'second' }
		];
		expect(ids(sortBids(rows, { ...context({}), preferenceLevels: LEVELS }))).toEqual([
			'bob',
			'alice'
		]);
	});

	test('sorts an unresolvable preference id last, like an unset one', () => {
		const rows = [
			{ scholar: 'alice', preferenceid: 'deleted-level' },
			{ scholar: 'bob', preferenceid: 'first' }
		];
		expect(ids(sortBids(rows, { ...context({}), preferenceLevels: LEVELS }))).toEqual([
			'bob',
			'alice'
		]);
	});

	test('breaks a rank tie by balance, then family name', () => {
		const rows = [
			{ scholar: 'alice', preferenceid: 'first' },
			{ scholar: 'bob', preferenceid: 'first' },
			{ scholar: 'cara', preferenceid: 'first' }
		];
		expect(
			ids(
				sortBids(rows, {
					...context({ alice: 1, bob: 9, cara: 9 }),
					preferenceLevels: LEVELS
				})
			)
		).toEqual(['alice', 'bob', 'cara']);
	});

	// Both bids carry Infinity, and Infinity - Infinity is NaN. The old
	// comparator returned that NaN, so the balance and name tiebreakers were
	// skipped and the order was whatever the sort happened to leave behind.
	test('still applies the tiebreakers when NO bid has a preference', () => {
		const rows = [
			{ scholar: 'cara', preferenceid: null },
			{ scholar: 'alice', preferenceid: null },
			{ scholar: 'bob', preferenceid: null }
		];
		expect(
			ids(
				sortBids(rows, {
					...context({ alice: 1, bob: 9, cara: 5 }),
					preferenceLevels: LEVELS
				})
			)
		).toEqual(['alice', 'cara', 'bob']);
	});

	// The same case as it actually arises: a venue that never configured
	// preference levels, so every bid's preferenceid is null and the list is empty.
	test('orders bids in a venue with no preference levels configured', () => {
		const rows = [
			{ scholar: 'cara', preferenceid: null },
			{ scholar: 'bob', preferenceid: null },
			{ scholar: 'alice', preferenceid: null }
		];
		expect(
			ids(sortBids(rows, { ...context({ alice: 4, bob: 4, cara: 4 }), preferenceLevels: [] }))
		).toEqual(['alice', 'bob', 'cara']);
	});

	test('tolerates a null preferenceLevels list', () => {
		const rows = [
			{ scholar: 'bob', preferenceid: 'first' },
			{ scholar: 'alice', preferenceid: null }
		];
		expect(
			ids(sortBids(rows, { ...context({ alice: 1, bob: 1 }), preferenceLevels: null }))
		).toEqual(['alice', 'bob']);
	});

	test('does not mutate the input', () => {
		const rows = [
			{ scholar: 'alice', preferenceid: 'third' },
			{ scholar: 'bob', preferenceid: 'first' }
		];
		sortBids(rows, { ...context({}), preferenceLevels: LEVELS });
		expect(ids(rows)).toEqual(['alice', 'bob']);
	});
});
