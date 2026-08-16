import { describe, expect, test } from 'vitest';
import {
	duplicateAcrossRows,
	mintAmount,
	rowError,
	rowsFromParsed,
	type ImportRow,
	type ImportSubmissionType
} from './bulkImportRows';

const TYPES: ImportSubmissionType[] = [
	{ id: 'full', name: 'Full Paper', submission_cost: 10 },
	{ id: 'revision', name: 'Revision', submission_cost: 4 }
];

function row(over: Partial<ImportRow> = {}): ImportRow {
	return {
		title: 'A title',
		externalID: 'EXT-1',
		expertise: '',
		submissionType: 'full',
		previousID: '',
		note: '',
		...over
	};
}

describe('duplicateAcrossRows', () => {
	test('finds nothing when every external ID is distinct', () => {
		expect([...duplicateAcrossRows([row({ externalID: 'A' }), row({ externalID: 'B' })])]).toEqual(
			[]
		);
	});

	test('flags every row sharing an external ID, not just the later one', () => {
		const dupes = duplicateAcrossRows([
			row({ externalID: 'A' }),
			row({ externalID: 'B' }),
			row({ externalID: 'A' })
		]);
		expect([...dupes].sort()).toEqual([0, 2]);
	});

	test('ignores surrounding whitespace when comparing', () => {
		expect([
			...duplicateAcrossRows([row({ externalID: 'A' }), row({ externalID: ' A ' })])
		]).toEqual([0, 1]);
	});

	// Blank IDs are already reported as a missing external ID; counting them as
	// duplicates of each other would bury that behind a misleading message.
	test('does not treat blank external IDs as duplicates of each other', () => {
		expect([...duplicateAcrossRows([row({ externalID: '' }), row({ externalID: '  ' })])]).toEqual(
			[]
		);
	});
});

describe('rowError', () => {
	const context = { existingExternalIDs: new Set<string>(), duplicates: new Set<number>() };

	test('accepts a complete row', () => {
		expect(rowError(row(), 0, context)).toBeNull();
	});

	test('reports a missing title first', () => {
		expect(rowError(row({ title: '   ', externalID: '' }), 0, context)).toBe('title');
	});

	test('reports a missing external ID', () => {
		expect(rowError(row({ externalID: ' ' }), 0, context)).toBe('externalID');
	});

	test('reports a collision with a submission already in the venue', () => {
		expect(
			rowError(row({ externalID: 'EXT-1' }), 0, {
				...context,
				existingExternalIDs: new Set(['EXT-1'])
			})
		).toBe('duplicateExisting');
	});

	test('reports a collision with another row in the batch', () => {
		expect(rowError(row(), 2, { ...context, duplicates: new Set([2]) })).toBe('duplicateRow');
	});

	test('prefers the existing-submission collision over the in-batch one', () => {
		expect(
			rowError(row({ externalID: 'EXT-1' }), 0, {
				existingExternalIDs: new Set(['EXT-1']),
				duplicates: new Set([0])
			})
		).toBe('duplicateExisting');
	});
});

describe('mintAmount', () => {
	test('sums each row’s submission type cost', () => {
		expect(
			mintAmount([row({ submissionType: 'full' }), row({ submissionType: 'revision' })], TYPES)
		).toBe(14);
	});

	test('is zero for no rows', () => {
		expect(mintAmount([], TYPES)).toBe(0);
	});

	// Documented, not endorsed: an unknown type under-mints silently rather than
	// failing. It cannot arise from the UI, where the type comes from a select.
	test('counts an unknown submission type as zero', () => {
		expect(mintAmount([row({ submissionType: 'ghost' })], TYPES)).toBe(0);
	});
});

describe('rowsFromParsed', () => {
	test('maps the lowercase header spellings a spreadsheet produces', () => {
		expect(
			rowsFromParsed([{ title: 'T', externalid: 'E', previousid: 'P' }], TYPES, 'full')
		).toEqual([
			{
				title: 'T',
				externalID: 'E',
				expertise: '',
				submissionType: 'full',
				previousID: 'P',
				note: ''
			}
		]);
	});

	test('also accepts the camelCase spellings', () => {
		const [r] = rowsFromParsed([{ externalID: 'E', previousID: 'P' }], TYPES, 'full');
		expect(r.externalID).toBe('E');
		expect(r.previousID).toBe('P');
	});

	test('matches a submission type by name, case-insensitively', () => {
		const [r] = rowsFromParsed([{ submission_type: '  full paper ' }], TYPES, 'revision');
		expect(r.submissionType).toBe('full');
	});

	test('falls back to the default type when the name is unknown or absent', () => {
		expect(
			rowsFromParsed([{ submission_type: 'Poster' }], TYPES, 'revision')[0].submissionType
		).toBe('revision');
		expect(rowsFromParsed([{}], TYPES, 'revision')[0].submissionType).toBe('revision');
	});

	test('fills every missing column with an empty string, never undefined', () => {
		const [r] = rowsFromParsed([{}], TYPES, 'full');
		expect(Object.values(r).every((v) => v !== undefined)).toBe(true);
		expect(r.title).toBe('');
	});
});
