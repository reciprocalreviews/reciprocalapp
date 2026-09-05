import { describe, expect, test } from 'vitest';
import {
	distinctTypeValues,
	duplicateAcrossRows,
	guessTypeAssignments,
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
		people: {},
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
				{},
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
				people: {}
			}
		]);
	});

	test('reads a CSV already using the importer own column names', () => {
		const mapping = guessMapping(['title', 'externalid', 'previousid']);
		const [r] = rowsFromParsed(
			[{ title: 'T', externalid: 'E', previousid: 'P' }],
			mapping,
			{},
			'full'
		);
		expect(r.title).toBe('T');
		expect(r.externalID).toBe('E');
		expect(r.previousID).toBe('P');
	});

	test('leaves a field empty when nothing is mapped to it', () => {
		const mapping = guessMapping(['title']);
		const [r] = rowsFromParsed([{ title: 'T' }], mapping, {}, 'full');
		expect(r.externalID).toBe('');
		expect(r.expertise).toBe('');
	});

	test('gives each row the type its value was assigned', () => {
		const mapping = guessMapping(['submission_type']);
		const parsed = [{ submission_type: '  full paper ' }];
		const assignments = guessTypeAssignments(
			distinctTypeValues(parsed, mapping.submissionType),
			TYPES,
			'revision'
		);
		const [r] = rowsFromParsed(parsed, mapping, {}, 'revision', assignments);
		expect(r.submissionType).toBe('full');
	});

	test('falls back to the default when a value has no assignment', () => {
		const mapping = guessMapping(['submission_type']);
		expect(
			rowsFromParsed([{ submission_type: 'Poster' }], mapping, {}, 'revision')[0].submissionType
		).toBe('revision');
		expect(rowsFromParsed([{}], mapping, {}, 'revision')[0].submissionType).toBe('revision');
	});

	test('fills every missing column with an empty string, never undefined', () => {
		const [r] = rowsFromParsed([{}], guessMapping(['title']), {}, 'full');
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
			{},
			'full'
		);
		expect(r.title).toBe('Flexible Deadlines: A Systematic Review');
	});

	test('collapses the other single-line fields too', () => {
		const mapping = guessMapping(['externalid', 'expertise', 'previousid']);
		const [r] = rowsFromParsed(
			[{ externalid: ' E\n1 ', expertise: 'a\n b', previousid: 'P\n2' }],
			mapping,
			{},
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
			{},
			'full'
		);
		expect(r.note).toBe('AE: Petersen\nEIC: Ko\n3 invited');
	});
});

describe('rowError with person columns', () => {
	const context = (over: Partial<Parameters<typeof rowError>[2]> = {}) => ({
		existingExternalIDs: new Set<string>(),
		duplicates: new Set<number>(),
		...over
	});

	test('reports a row naming somebody the venue could not identify', () => {
		expect(
			rowError(row({ people: { ae: 'Nobody' } }), 0, context({ personUnresolved: new Set([0]) }))
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
		expect(rowError(row({ people: { ae: 'Anybody' } }), 0, context())).toBeNull();
	});
});

describe('rowsFromParsed role columns', () => {
	// The case the feature exists for, and one no heuristic could produce: the
	// column called "Editor" feeds the ASSOCIATE editor role, while "Editor in
	// Chief" feeds the top one. Only the editor knows that.
	test('reads each role from the column matched to it, however they cross', () => {
		const mapping = guessMapping(['Manuscript Title', 'Editor in Chief', 'Editor']);
		const roleColumns = { 'role-editor': 'Editor in Chief', 'role-ae': 'Editor' };
		const [r] = rowsFromParsed(
			[{ 'Manuscript Title': 'T', 'Editor in Chief': 'Ko, Amy', Editor: 'Petersen, Andrew' }],
			mapping,
			roleColumns,
			'full'
		);
		expect(r.people['role-editor']).toBe('Ko, Amy');
		expect(r.people['role-ae']).toBe('Petersen, Andrew');
	});

	test('gives a role with no column no key at all', () => {
		const [r] = rowsFromParsed(
			[{ Editor: 'Petersen, Andrew' }],
			guessMapping(['title']),
			{},
			'full'
		);
		expect(r.people).toEqual({});
	});

	// Present and empty, not absent: a field bound to a missing key would meet an
	// undefined where it expects a string.
	test('gives a blank cell an empty string rather than no key', () => {
		const [r] = rowsFromParsed([{ Editor: '' }], guessMapping(['title']), { ae: 'Editor' }, 'full');
		expect(r.people).toEqual({ ae: '' });
	});

	test('collapses a name wrapped across two lines', () => {
		const [r] = rowsFromParsed(
			[{ Editor: 'Petersen,\nAndrew' }],
			guessMapping(['title']),
			{ ae: 'Editor' },
			'full'
		);
		expect(r.people.ae).toBe('Petersen, Andrew');
	});
});

describe('distinctTypeValues', () => {
	const parsed = [
		{ Type: 'Paper' },
		{ Type: 'Paper' },
		{ Type: 'Special Issue' },
		{ Type: '' },
		{ Type: '  paper  ' }
	];

	test('counts each distinct value, most common first', () => {
		expect(distinctTypeValues(parsed, 'Type')).toEqual([
			{ value: 'Paper', count: 3 },
			{ value: 'Special Issue', count: 1 }
		]);
	});

	test('reads nothing when no type column is matched', () => {
		expect(distinctTypeValues(parsed, null)).toEqual([]);
	});
});

describe('guessTypeAssignments', () => {
	test('pre-fills a value with the type of the same name', () => {
		const assignments = guessTypeAssignments([{ value: 'Full Paper' }], TYPES, 'revision');
		expect(assignments['full paper']).toBe('full');
	});

	// The normal case: a venue's type names are its own, and a file's are its own.
	// This used to happen per row in silence, and the default type's cost then set
	// the mint.
	test('pre-fills a value matching nothing with the default', () => {
		const assignments = guessTypeAssignments([{ value: 'Paper' }], TYPES, 'revision');
		expect(assignments['paper']).toBe('revision');
	});
});
