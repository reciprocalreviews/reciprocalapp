import { describe, expect, test } from 'vitest';
import {
	looksLikeEmail,
	parseAssignFromListResult,
	parseAssignmentList,
	repeatedLines,
	resolveWho,
	toListAssignment
} from './assignmentList';
import type { Volunteer } from './matchPersonName';

function volunteer(id: string, name: string, email: string | null = null): Volunteer {
	return { id, name, email, orcid: null, profile: undefined };
}

const PETERSEN = volunteer('p', 'Andrew Petersen', 'apetersen@example.edu');
const SOH = volunteer('s', 'Leen-Kiat Soh', 'lksoh@example.edu');
const SOH_TOO = volunteer('s2', 'Leen-Kiat Soh', 'other@example.edu');

describe('parseAssignmentList', () => {
	test('reads two spreadsheet columns, ignoring any after them', () => {
		expect(parseAssignmentList('TOCE-1\tAndrew Petersen\tnotes\nTOCE-2\tLeen-Kiat Soh')).toEqual([
			{ externalID: 'TOCE-1', written: 'Andrew Petersen' },
			{ externalID: 'TOCE-2', written: 'Leen-Kiat Soh' }
		]);
	});

	test('splits a typed line at its first comma only, keeping "Surname, Given" whole', () => {
		expect(parseAssignmentList('TOCE-1, Petersen, Andrew')).toEqual([
			{ externalID: 'TOCE-1', written: 'Petersen, Andrew' }
		]);
	});

	test('accepts a semicolon, trims both cells, and drops blank lines', () => {
		expect(parseAssignmentList('\r\n  TOCE-1 ;  a@b.edu  \r\n\n')).toEqual([
			{ externalID: 'TOCE-1', written: 'a@b.edu' }
		]);
	});

	test('a line with only an ID names nobody', () => {
		expect(parseAssignmentList('TOCE-1')).toEqual([{ externalID: 'TOCE-1', written: '' }]);
	});

	test('keeps a header row as a line, which the database then finds no manuscript for', () => {
		expect(parseAssignmentList('Manuscript ID\tEditor')[0]).toEqual({
			externalID: 'Manuscript ID',
			written: 'Editor'
		});
	});
});

describe('resolveWho', () => {
	const candidates = [PETERSEN, SOH];

	test('resolves a name as the importer does, in either order', () => {
		expect(resolveWho('Petersen, Andrew', candidates)).toEqual({ status: 'resolved', id: 'p' });
	});

	test('resolves an email address only to the volunteer it belongs to, ignoring case', () => {
		expect(resolveWho('LKSoh@Example.edu', candidates)).toEqual({ status: 'resolved', id: 's' });
		expect(resolveWho('nobody@example.edu', candidates)).toEqual({ status: 'unmatched' });
	});

	test('reports a name several volunteers share as ambiguous', () => {
		expect(resolveWho('Leen-Kiat Soh', [SOH, SOH_TOO]).status).toBe('ambiguous');
	});

	test('a pinned choice wins only while it is still a candidate', () => {
		expect(resolveWho('Leen-Kiat Soh', [SOH, SOH_TOO], 's2')).toEqual({
			status: 'resolved',
			id: 's2'
		});
		expect(resolveWho('Leen-Kiat Soh', [SOH, SOH_TOO], 'gone').status).toBe('ambiguous');
	});

	test('an empty cell names nobody', () => {
		expect(resolveWho('', candidates)).toEqual({ status: 'none' });
	});
});

describe('repeatedLines', () => {
	test('flags every line after the first naming a manuscript', () => {
		const lines = parseAssignmentList('A\tx\nB\ty\nA\tz\nA\tw');
		expect([...repeatedLines(lines)]).toEqual([2, 3]);
	});
});

describe('toListAssignment', () => {
	const line = { externalID: 'TOCE-1', written: 'Jane Doe' };

	test('sends a resolved scholar', () => {
		expect(toListAssignment(line, { status: 'resolved', id: 'p' })).toEqual({
			externalid: 'TOCE-1',
			person: 'p'
		});
	});

	test('keeps an unmatched name, but not an unmatched email address', () => {
		expect(toListAssignment(line, { status: 'unmatched' })).toEqual({
			externalid: 'TOCE-1',
			name: 'Jane Doe'
		});
		expect(
			toListAssignment({ externalID: 'TOCE-1', written: 'j@x.edu' }, { status: 'unmatched' })
		).toBeNull();
	});

	test('sends nothing for an ambiguous name, an empty cell, or a missing ID', () => {
		expect(toListAssignment(line, { status: 'ambiguous', candidates: [] })).toBeNull();
		expect(toListAssignment(line, { status: 'none' })).toBeNull();
		expect(
			toListAssignment({ externalID: '', written: 'Jane' }, { status: 'unmatched' })
		).toBeNull();
	});
});

describe('looksLikeEmail', () => {
	test('tells an address from a name', () => {
		expect(looksLikeEmail('a@b.edu')).toBe(true);
		expect(looksLikeEmail('Andrew Petersen')).toBe(false);
	});
});

describe('parseAssignFromListResult', () => {
	const valid = {
		rows: [
			{ externalid: 'A', submission: 'id', title: 'T', verdict: 'seated', holder: null },
			{ externalid: 'B', submission: null, title: null, verdict: 'missing', holder: null }
		],
		seated: 1,
		seated_by: { p: 1 },
		kept: 0,
		skipped: 1
	};

	test('reads what assign_submissions returns', () => {
		expect(parseAssignFromListResult(valid)).toEqual({
			rows: valid.rows,
			seated: 1,
			seatedBy: { p: 1 },
			kept: 0,
			skipped: 1
		});
	});

	test('refuses an unknown verdict or a missing count', () => {
		expect(
			parseAssignFromListResult({ ...valid, rows: [{ ...valid.rows[0], verdict: 'maybe' }] })
		).toBeNull();
		expect(parseAssignFromListResult({ ...valid, seated: undefined })).toBeNull();
		expect(parseAssignFromListResult(null)).toBeNull();
	});
});
