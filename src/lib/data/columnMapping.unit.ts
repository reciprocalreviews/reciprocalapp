import { describe, expect, test } from 'vitest';
import { guessMapping, normalizeHeader, normalizeKey, unmappedHeaders } from './columnMapping';

describe('normalizeHeader', () => {
	test('splits a header into lowercase words', () => {
		expect(normalizeHeader('Manuscript ID')).toEqual(['manuscript', 'id']);
	});

	test('treats separators, punctuation and case alike', () => {
		expect(normalizeHeader('submission_type')).toEqual(['submission', 'type']);
		expect(normalizeHeader('Submission-Type')).toEqual(['submission', 'type']);
		expect(normalizeHeader('  SUBMISSION   TYPE  ')).toEqual(['submission', 'type']);
	});

	test('reduces spellings of one name to a single key', () => {
		expect(normalizeKey('External ID')).toBe('externalid');
		expect(normalizeKey('external_id')).toBe('externalid');
		expect(normalizeKey('externalid')).toBe('externalid');
	});
});

describe('guessMapping with the importer own column names', () => {
	test('maps a CSV already in the importer shape to itself', () => {
		const mapping = guessMapping([
			'title',
			'externalid',
			'expertise',
			'submission_type',
			'previousid',
			'note'
		]);
		expect(mapping).toEqual({
			title: 'title',
			externalID: 'externalid',
			expertise: 'expertise',
			submissionType: 'submission_type',
			previousID: 'previousid',
			note: 'note',
			person: null
		});
	});
});

// The point of these is that no product is named anywhere in the module. Each
// shape below is a different way of saying the same six things.
describe('guessMapping generality', () => {
	test('reads a terse header row', () => {
		const mapping = guessMapping(['id', 'title', 'type', 'keywords']);
		expect(mapping.externalID).toBe('id');
		expect(mapping.title).toBe('title');
		expect(mapping.submissionType).toBe('type');
		expect(mapping.expertise).toBe('keywords');
	});

	test('reads verbose multi-word headers', () => {
		const mapping = guessMapping([
			'Manuscript ID',
			'Manuscript Title',
			'Manuscript Type',
			'Date Submitted',
			'Status'
		]);
		expect(mapping.externalID).toBe('Manuscript ID');
		expect(mapping.title).toBe('Manuscript Title');
		expect(mapping.submissionType).toBe('Manuscript Type');
		expect(mapping.note).toBe('Status');
	});

	test('reads snake_case headers in a different order', () => {
		const mapping = guessMapping(['paper_track', 'paper_number', 'paper_title', 'subject_areas']);
		expect(mapping.externalID).toBe('paper_number');
		expect(mapping.title).toBe('paper_title');
		expect(mapping.submissionType).toBe('paper_track');
		expect(mapping.expertise).toBe('subject_areas');
	});

	test('reads a third vocabulary again', () => {
		const mapping = guessMapping(['Submission number', 'Paper title', 'Category', 'Topics']);
		expect(mapping.externalID).toBe('Submission number');
		expect(mapping.title).toBe('Paper title');
		expect(mapping.submissionType).toBe('Category');
		expect(mapping.expertise).toBe('Topics');
	});

	test('leaves columns it has no concept for alone', () => {
		const headers = ['Manuscript ID', 'Date Submitted', 'Submitting Author', 'Country'];
		const mapping = guessMapping(headers);
		expect(mapping.title).toBeNull();
		expect(unmappedHeaders(headers, mapping)).toEqual([
			'Date Submitted',
			'Submitting Author',
			'Country'
		]);
	});
});

describe('guessMapping precedence', () => {
	test('takes a previous-identifier column as the predecessor, not the external ID', () => {
		const mapping = guessMapping(['Manuscript ID', 'Previous Manuscript ID', 'Title']);
		expect(mapping.previousID).toBe('Previous Manuscript ID');
		expect(mapping.externalID).toBe('Manuscript ID');
	});

	test('does not take a previous column that names no identifier', () => {
		const mapping = guessMapping(['Original Title', 'Manuscript ID']);
		expect(mapping.previousID).toBeNull();
	});

	test('prefers the column that names the concept over one that mentions it', () => {
		// The narrower header wins: "Editor" is the editor column, while "Editor
		// in Chief" is a column that happens to contain the word.
		const mapping = guessMapping(['Editor in Chief', 'Editor']);
		expect(mapping.person).toBe('Editor');
	});

	test('never reads one column into two fields', () => {
		const mapping = guessMapping(['Title', 'ID']);
		const used = Object.values(mapping).filter((h) => h !== null);
		expect(new Set(used).size).toBe(used.length);
	});
});

describe('guessMapping declines rather than guessing', () => {
	// Whichever came first in the file is not a reason to prefer it.
	test('leaves a field unmapped when two columns fit equally well', () => {
		expect(guessMapping(['Paper ID', 'Review ID']).externalID).toBeNull();
	});

	test('maps nothing at all when no header describes anything', () => {
		expect(guessMapping(['alpha', 'beta', 'gamma'])).toEqual({
			title: null,
			externalID: null,
			expertise: null,
			submissionType: null,
			previousID: null,
			note: null,
			person: null
		});
	});

	test('handles an empty header row', () => {
		expect(guessMapping([]).title).toBeNull();
	});
});

describe('guessMapping with a narrowed field set', () => {
	// A caller that offers no person column must not quietly claim a header for
	// it, or that column disappears from the ignored-columns report while
	// feeding nothing.
	test('does not claim a header for a field it was not asked about', () => {
		const headers = ['Manuscript ID', 'Manuscript Title', 'Editor'];
		const fields = ['title', 'externalID'] as const;
		const mapping = guessMapping(headers, [...fields]);
		expect(mapping.person).toBeNull();
		expect(unmappedHeaders(headers, mapping)).toEqual(['Editor']);
	});

	test('still maps the fields it was asked about', () => {
		const mapping = guessMapping(['Manuscript ID', 'Manuscript Title'], ['title', 'externalID']);
		expect(mapping.title).toBe('Manuscript Title');
		expect(mapping.externalID).toBe('Manuscript ID');
	});
});
