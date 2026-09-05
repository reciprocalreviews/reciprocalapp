import { describe, expect, test } from 'vitest';
import {
	duplicateAcrossRows,
	mintAmount,
	rowError,
	rowsFromParsed,
	type ImportRow,
	type ImportSubmissionType
} from './bulkImportRows';
import { guessMapping } from './columnMapping';

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
		person: '',
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
	test('reads each field from the column mapped to it', () => {
		const mapping = guessMapping(['Manuscript Title', 'Manuscript ID', 'Previous Paper ID']);
		expect(
			rowsFromParsed(
				[{ 'Manuscript Title': 'T', 'Manuscript ID': 'E', 'Previous Paper ID': 'P' }],
				mapping,
				TYPES,
				'full'
			)
		).toEqual([
			{
				title: 'T',
				externalID: 'E',
				expertise: '',
				submissionType: 'full',
				previousID: 'P',
				note: '',
				person: ''
			}
		]);
	});

	test('reads a CSV already using the importer own column names', () => {
		const mapping = guessMapping(['title', 'externalid', 'previousid']);
		const [r] = rowsFromParsed(
			[{ title: 'T', externalid: 'E', previousid: 'P' }],
			mapping,
			TYPES,
			'full'
		);
		expect(r.title).toBe('T');
		expect(r.externalID).toBe('E');
		expect(r.previousID).toBe('P');
	});

	test('leaves a field empty when nothing is mapped to it', () => {
		const mapping = guessMapping(['title']);
		const [r] = rowsFromParsed([{ title: 'T' }], mapping, TYPES, 'full');
		expect(r.externalID).toBe('');
		expect(r.expertise).toBe('');
	});

	test('matches a submission type by name, case-insensitively', () => {
		const mapping = guessMapping(['submission_type']);
		const [r] = rowsFromParsed([{ submission_type: '  full paper ' }], mapping, TYPES, 'revision');
		expect(r.submissionType).toBe('full');
	});

	test('falls back to the default type when the name is unknown or absent', () => {
		const mapping = guessMapping(['submission_type']);
		expect(
			rowsFromParsed([{ submission_type: 'Poster' }], mapping, TYPES, 'revision')[0].submissionType
		).toBe('revision');
		expect(rowsFromParsed([{}], mapping, TYPES, 'revision')[0].submissionType).toBe('revision');
	});

	test('fills every missing column with an empty string, never undefined', () => {
		const [r] = rowsFromParsed([{}], guessMapping(['title']), TYPES, 'full');
		expect(Object.values(r).every((v) => v !== undefined)).toBe(true);
		expect(r.title).toBe('');
	});
});

describe('rowsFromParsed whitespace', () => {
	// An export that wrapped a long title across two lines should not put a
	// newline through a single-line field and into the database.
	test('collapses a wrapped title onto one line', () => {
		const mapping = guessMapping(['title']);
		const [r] = rowsFromParsed(
			[{ title: 'Flexible Deadlines:\nA Systematic Review' }],
			mapping,
			TYPES,
			'full'
		);
		expect(r.title).toBe('Flexible Deadlines: A Systematic Review');
	});

	test('collapses the other single-line fields too', () => {
		const mapping = guessMapping(['externalid', 'expertise', 'previousid']);
		const [r] = rowsFromParsed(
			[{ externalid: ' E\n1 ', expertise: 'a\n b', previousid: 'P\n2' }],
			mapping,
			TYPES,
			'full'
		);
		expect(r.externalID).toBe('E 1');
		expect(r.expertise).toBe('a b');
		expect(r.previousID).toBe('P 2');
	});

	// The note is where a multi-line status column lands, and its lines are its
	// content.
	test('keeps the line structure of the note', () => {
		const mapping = guessMapping(['Status']);
		const [r] = rowsFromParsed(
			[{ Status: 'AE: Petersen\nEIC: Ko\n3 invited' }],
			mapping,
			TYPES,
			'full'
		);
		expect(r.note).toBe('AE: Petersen\nEIC: Ko\n3 invited');
	});
});

describe('rowError with a person column', () => {
	const context = (over: Partial<Parameters<typeof rowError>[2]> = {}) => ({
		existingExternalIDs: new Set<string>(),
		duplicates: new Set<number>(),
		...over
	});

	test('reports a row naming somebody the venue could not identify', () => {
		expect(
			rowError(row({ person: 'Nobody' }), 0, context({ personUnresolved: new Set([0]) }))
		).toBe('personUnresolved');
	});

	test('says nothing about rows whose person resolved', () => {
		expect(rowError(row(), 1, context({ personUnresolved: new Set([0]) }))).toBeNull();
	});

	// The checks that were here first keep reporting first: a row missing its
	// title has a more basic problem than one whose editor could not be named.
	test('reports a missing title ahead of an unresolved person', () => {
		expect(rowError(row({ title: '' }), 0, context({ personUnresolved: new Set([0]) }))).toBe(
			'title'
		);
	});

	test('reports a duplicate ahead of an unresolved person', () => {
		expect(
			rowError(row(), 0, context({ duplicates: new Set([0]), personUnresolved: new Set([0]) }))
		).toBe('duplicateRow');
	});

	// A caller that offers no person column has nobody to resolve.
	test('works without the person set at all', () => {
		expect(rowError(row({ person: 'Anybody' }), 0, context())).toBeNull();
	});
});

describe('rowsFromParsed person column', () => {
	test('reads the person from the column mapped to it', () => {
		const mapping = guessMapping(['Editor'], ['person']);
		const [r] = rowsFromParsed([{ Editor: 'Petersen, Andrew' }], mapping, TYPES, 'full');
		expect(r.person).toBe('Petersen, Andrew');
	});

	test('leaves the person empty when no column is mapped', () => {
		const [r] = rowsFromParsed(
			[{ Editor: 'Petersen, Andrew' }],
			guessMapping(['title']),
			TYPES,
			'full'
		);
		expect(r.person).toBe('');
	});
});
