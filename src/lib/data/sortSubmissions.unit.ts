import { describe, expect, test } from 'vitest';
import {
	NULL_TRANSACTION,
	submissionsView,
	type SubmissionsViewContext,
	type ViewSubmission
} from './sortSubmissions';

const NOW = Date.parse('2026-08-16T00:00:00Z');
const DAY = 24 * 60 * 60 * 1000;

function sub(over: Partial<ViewSubmission> & { id: string }): ViewSubmission {
	return {
		title: 'Title',
		externalid: 'EXT',
		authors: [],
		status: 'reviewing',
		created_at: '2026-01-01T00:00:00Z',
		completed_at: null,
		transactions: [],
		...over
	};
}

function view(over: Partial<SubmissionsViewContext> = {}) {
	return submissionsView({
		uid: 'viewer',
		isAdmin: false,
		assignments: [],
		rolesById: new Map(),
		scholarName: new Map(),
		conflicts: [],
		transactions: [],
		doneVisibilityDays: 30,
		filter: '',
		now: NOW,
		sortOrder: ['payment', 'title', 'id', 'created'],
		paymentSortPendingFirst: true,
		titleSortIncreasing: true,
		idSortIncreasing: true,
		createdSortLatestFirst: true,
		...over
	});
}

const ids = (rows: ViewSubmission[]) => rows.map((r) => r.id);

describe('canSeeAuthors', () => {
	const target = sub({ id: 's1', authors: ['author'] });

	test('an admin always can', () => {
		expect(view({ isAdmin: true, assignments: null }).canSeeAuthors(target)).toBe(true);
	});

	test('an author of the submission always can', () => {
		expect(view({ uid: 'author' }).canSeeAuthors(target)).toBe(true);
	});

	test('an unassigned scholar cannot', () => {
		expect(view({ assignments: [] }).canSeeAuthors(target)).toBe(false);
	});

	test('an assigned reviewer in an open role can', () => {
		expect(
			view({
				assignments: [{ submission: 's1', scholar: 'viewer', role: 'r1' }],
				rolesById: new Map([['r1', { anonymous_authors: false }]])
			}).canSeeAuthors(target)
		).toBe(true);
	});

	test('an assigned reviewer in an anonymous-authors role cannot', () => {
		expect(
			view({
				assignments: [{ submission: 's1', scholar: 'viewer', role: 'r1' }],
				rolesById: new Map([['r1', { anonymous_authors: true }]])
			}).canSeeAuthors(target)
		).toBe(false);
	});

	// Any anonymous role the viewer holds on this submission closes the gate,
	// even if they hold an open role too.
	test('one anonymous-authors role is enough to close the gate', () => {
		expect(
			view({
				assignments: [
					{ submission: 's1', scholar: 'viewer', role: 'open' },
					{ submission: 's1', scholar: 'viewer', role: 'anon' }
				],
				rolesById: new Map([
					['open', { anonymous_authors: false }],
					['anon', { anonymous_authors: true }]
				])
			}).canSeeAuthors(target)
		).toBe(false);
	});

	test('an assignment on a different submission does not count', () => {
		expect(
			view({
				assignments: [{ submission: 'other', scholar: 'viewer', role: 'r1' }],
				rolesById: new Map([['r1', { anonymous_authors: false }]])
			}).canSeeAuthors(target)
		).toBe(false);
	});

	test('unloaded assignments close the gate rather than opening it', () => {
		expect(view({ assignments: null }).canSeeAuthors(target)).toBe(false);
	});
});

describe('matchesFilter', () => {
	const target = sub({ id: 's1', title: 'Deep Learning', externalid: 'EXT-42', authors: ['a1'] });

	test('matches title and external id case-insensitively', () => {
		expect(view({ filter: 'deep' }).matchesFilter(target)).toBe(true);
		expect(view({ filter: 'ext-4' }).matchesFilter(target)).toBe(true);
	});

	test('does not match unrelated text', () => {
		expect(view({ filter: 'zzz' }).matchesFilter(target)).toBe(false);
	});

	test('matches an assigned reviewer name', () => {
		expect(
			view({
				filter: 'baker',
				assignments: [{ submission: 's1', scholar: 'rev', role: 'r1' }],
				scholarName: new Map([['rev', 'bob baker']])
			}).matchesFilter(target)
		).toBe(true);
	});

	// The privacy point: search must not become a side channel for author
	// identity that the Authors column itself would hide.
	test('does not match an author name the viewer may not see', () => {
		expect(
			view({
				filter: 'adams',
				scholarName: new Map([['a1', 'alice adams']]),
				assignments: [{ submission: 's1', scholar: 'viewer', role: 'anon' }],
				rolesById: new Map([['anon', { anonymous_authors: true }]])
			}).matchesFilter(target)
		).toBe(false);
	});

	test('does match an author name the viewer may see', () => {
		expect(
			view({
				filter: 'adams',
				scholarName: new Map([['a1', 'alice adams']]),
				isAdmin: true
			}).matchesFilter(target)
		).toBe(true);
	});
});

describe('paymentStatus', () => {
	test('is undefined until transactions load', () => {
		expect(view({ transactions: null }).paymentStatus(sub({ id: 's1' }))).toBeUndefined();
	});

	test('counts charges with no visible transaction', () => {
		const target = sub({ id: 's1', transactions: ['t1', 't2'] });
		expect(view({ transactions: [{ id: 't1' }] }).paymentStatus(target)).toBe(1);
	});

	test('is zero when every charge is visible', () => {
		const target = sub({ id: 's1', transactions: ['t1'] });
		expect(view({ transactions: [{ id: 't1' }] }).paymentStatus(target)).toBe(0);
	});

	test('ignores non-paying co-author placeholder slots', () => {
		const target = sub({ id: 's1', transactions: [NULL_TRANSACTION, NULL_TRANSACTION] });
		expect(view({ transactions: [] }).paymentStatus(target)).toBe(0);
	});
});

describe('sortedAndFiltered', () => {
	test('hides submissions the viewer has a conflict on', () => {
		const rows = [sub({ id: 's1' }), sub({ id: 's2' })];
		expect(ids(view({ conflicts: [{ submissionid: 's1' }] }).sortedAndFiltered(rows))).toEqual([
			's2'
		]);
	});

	test('sorts done submissions to the bottom regardless of the active sort', () => {
		const rows = [
			sub({ id: 'done', status: 'done', title: 'A', completed_at: '2026-08-15T00:00:00Z' }),
			sub({ id: 'live', status: 'reviewing', title: 'Z' })
		];
		expect(ids(view().sortedAndFiltered(rows))).toEqual(['live', 'done']);
	});

	test('hides done submissions older than the visibility window', () => {
		const rows = [
			sub({
				id: 'old',
				status: 'done',
				completed_at: new Date(NOW - 40 * DAY).toISOString()
			}),
			sub({ id: 'recent', status: 'done', completed_at: new Date(NOW - 5 * DAY).toISOString() })
		];
		expect(ids(view({ doneVisibilityDays: 30 }).sortedAndFiltered(rows))).toEqual(['recent']);
	});

	test('keeps a done submission that has no completion timestamp', () => {
		const rows = [sub({ id: 'x', status: 'done', completed_at: null })];
		expect(ids(view({ doneVisibilityDays: 1 }).sortedAndFiltered(rows))).toEqual(['x']);
	});

	test('the last column in sortOrder is the dominant key', () => {
		const rows = [
			sub({ id: 'a', title: 'B', created_at: '2026-01-02T00:00:00Z' }),
			sub({ id: 'b', title: 'A', created_at: '2026-01-01T00:00:00Z' })
		];
		// created is last, and latest-first, so the newer one leads despite title.
		expect(ids(view().sortedAndFiltered(rows))).toEqual(['a', 'b']);
	});

	// The regression this module exists for. `sort` then `reverse` inverted the
	// tie-break established by the previous pass, so with the default
	// newest-first setting, same-day submissions came back Z..A by title.
	test('breaks a created_at tie by ASCENDING title even when created is descending', () => {
		const rows = [
			sub({ id: 'b', title: 'B', created_at: '2026-01-01T00:00:00Z' }),
			sub({ id: 'a', title: 'A', created_at: '2026-01-01T00:00:00Z' }),
			sub({ id: 'c', title: 'C', created_at: '2026-01-02T00:00:00Z' })
		];
		expect(
			ids(
				view({ sortOrder: ['title', 'created'], createdSortLatestFirst: true }).sortedAndFiltered(
					rows
				)
			)
		).toEqual(['c', 'a', 'b']);
	});

	test('created ascending still breaks ties by ascending title', () => {
		const rows = [
			sub({ id: 'b', title: 'B', created_at: '2026-01-02T00:00:00Z' }),
			sub({ id: 'a', title: 'A', created_at: '2026-01-02T00:00:00Z' }),
			sub({ id: 'c', title: 'C', created_at: '2026-01-01T00:00:00Z' })
		];
		expect(
			ids(
				view({ sortOrder: ['title', 'created'], createdSortLatestFirst: false }).sortedAndFiltered(
					rows
				)
			)
		).toEqual(['c', 'a', 'b']);
	});

	test('descending title is a real reversal of the title order', () => {
		const rows = [sub({ id: 'a', title: 'A' }), sub({ id: 'b', title: 'B' })];
		expect(
			ids(view({ sortOrder: ['title'], titleSortIncreasing: false }).sortedAndFiltered(rows))
		).toEqual(['b', 'a']);
	});

	test('an empty filter keeps everything', () => {
		const rows = [sub({ id: 's1', title: 'X' }), sub({ id: 's2', title: 'Y' })];
		expect(ids(view({ filter: '   ' }).sortedAndFiltered(rows))).toEqual(['s1', 's2']);
	});

	test('a filter narrows to matches', () => {
		const rows = [sub({ id: 's1', title: 'Alpha' }), sub({ id: 's2', title: 'Beta' })];
		expect(ids(view({ filter: 'alph' }).sortedAndFiltered(rows))).toEqual(['s1']);
	});
});
