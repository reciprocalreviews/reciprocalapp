import { describe, expect, test } from 'vitest';
import parseCSV from './parseCSV';

describe('parseCSV', () => {
	test('returns empty array when only header is present', () => {
		expect(parseCSV('a,b,c').rows).toEqual([]);
	});

	test('returns empty array for empty input', () => {
		expect(parseCSV('').rows).toEqual([]);
	});

	test('parses a basic header + row', () => {
		expect(parseCSV('title,externalid\nFoo,123').rows).toEqual([
			{ title: 'Foo', externalid: '123' }
		]);
	});

	test('handles CRLF line endings', () => {
		expect(parseCSV('title,externalid\r\nFoo,123\r\nBar,456').rows).toEqual([
			{ title: 'Foo', externalid: '123' },
			{ title: 'Bar', externalid: '456' }
		]);
	});

	test('skips blank lines', () => {
		expect(parseCSV('title,externalid\n\nFoo,123\n\n').rows).toEqual([
			{ title: 'Foo', externalid: '123' }
		]);
	});

	test('handles quoted fields with commas', () => {
		expect(parseCSV('title,note\n"Foo, the bar","hello, world"').rows).toEqual([
			{ title: 'Foo, the bar', note: 'hello, world' }
		]);
	});

	test('handles escaped quotes inside quoted fields', () => {
		expect(parseCSV('title,note\n"He said ""hi""","quoted ""text"" here"').rows).toEqual([
			{ title: 'He said "hi"', note: 'quoted "text" here' }
		]);
	});

	test('trims header and cell whitespace', () => {
		expect(parseCSV(' title , externalid \n  Foo  ,  123  ').rows).toEqual([
			{ title: 'Foo', externalid: '123' }
		]);
	});

	test('fills missing trailing cells with empty strings', () => {
		expect(parseCSV('title,externalid,note\nFoo,123').rows).toEqual([
			{ title: 'Foo', externalid: '123', note: '' }
		]);
	});
});

describe('parseCSV ragged-row reporting', () => {
	test('reports nothing when every row matches the header', () => {
		expect(parseCSV('a,b\n1,2\n3,4').ragged).toEqual([]);
	});

	// Extra cells are dropped to keep the record shape stable, but dropping them
	// in silence is what let a bad import look successful.
	test('reports a row with more cells than the header, and still drops them', () => {
		const { rows, ragged } = parseCSV('title,externalid\nFoo,1,DROPPED');
		expect(rows).toEqual([{ title: 'Foo', externalid: '1' }]);
		expect(ragged).toEqual([{ line: 2, cells: 3, expected: 2 }]);
	});

	test('reports a row with fewer cells than the header', () => {
		expect(parseCSV('a,b,c\n1,2').ragged).toEqual([{ line: 2, cells: 2, expected: 3 }]);
	});

	// The motivating case: one unquoted comma in a title shifts every column and
	// pushes the last field off the end.
	test('reports the column shift caused by an unquoted comma', () => {
		const { rows, ragged } = parseCSV('title,externalid,note\nSmith, Jones and Co,42,hi');
		expect(rows).toEqual([{ title: 'Smith', externalid: 'Jones and Co', note: '42' }]);
		expect(ragged).toEqual([{ line: 2, cells: 4, expected: 3 }]);
	});

	test('numbers lines so they match a spreadsheet, counting the header as line 1', () => {
		const { ragged } = parseCSV('a,b\n1,2\n3\n5,6,7');
		expect(ragged.map((r) => r.line)).toEqual([3, 4]);
	});

	test('a quoted comma is not ragged', () => {
		expect(parseCSV('title,note\n"Foo, the bar",hi').ragged).toEqual([]);
	});
});

describe('parseCSV multi-line records', () => {
	// The motivating case: reviewing platforms wrap long titles and export
	// multi-line status fields, and splitting on newlines shattered every one.
	test('keeps a newline inside a quoted field and does not split the record', () => {
		expect(parseCSV('title,note\n"Flexible Deadlines:\nA Review",hi').rows).toEqual([
			{ title: 'Flexible Deadlines:\nA Review', note: 'hi' }
		]);
	});

	test('normalizes a CRLF inside a quoted field to a newline', () => {
		expect(parseCSV('title,note\r\n"one\r\ntwo",hi').rows).toEqual([
			{ title: 'one\ntwo', note: 'hi' }
		]);
	});

	test('reads several multi-line records in a row', () => {
		const { rows, ragged } = parseCSV('a,b\n"1\n2",x\n"3\n4\n5",y');
		expect(rows).toEqual([
			{ a: '1\n2', b: 'x' },
			{ a: '3\n4\n5', b: 'y' }
		]);
		expect(ragged).toEqual([]);
	});

	// The line number has to survive the newlines it just consumed, or it points
	// at the wrong place in the file exactly when the file is hardest to read.
	test('reports a ragged record by the physical line it starts on', () => {
		const { ragged } = parseCSV('a,b\n"1\n2\n3",x\nBROKEN');
		expect(ragged).toEqual([{ line: 5, cells: 1, expected: 2 }]);
	});

	test('closes an unterminated quote at end of input rather than losing the record', () => {
		expect(parseCSV('title,note\nFoo,"never closed').rows).toEqual([
			{ title: 'Foo', note: 'never closed' }
		]);
	});
});

describe('parseCSV byte order mark', () => {
	test('strips a leading BOM from the first header', () => {
		const { rows } = parseCSV('﻿title,externalid\nFoo,123');
		expect(Object.keys(rows[0])).toEqual(['title', 'externalid']);
		expect(rows).toEqual([{ title: 'Foo', externalid: '123' }]);
	});

	test('strips a BOM ahead of a quoted first header', () => {
		expect(parseCSV('﻿"title","externalid"\nFoo,123').rows).toEqual([
			{ title: 'Foo', externalid: '123' }
		]);
	});
});

describe('parseCSV trailing empty header column', () => {
	// A header ending in a comma is common in real exports. It used to make every
	// data row ragged and add a column with no name.
	test('forgives a trailing empty header when data rows have no extra cell', () => {
		const { rows, ragged } = parseCSV('title,externalid,\nFoo,123');
		expect(rows).toEqual([{ title: 'Foo', externalid: '123' }]);
		expect(Object.keys(rows[0])).not.toContain('');
		expect(ragged).toEqual([]);
	});

	test('forgives a trailing empty header when data rows also end in a comma', () => {
		const { rows, ragged } = parseCSV('title,externalid,\nFoo,123,');
		expect(rows).toEqual([{ title: 'Foo', externalid: '123' }]);
		expect(ragged).toEqual([]);
	});

	// Forgiveness is capped at what the header asked for, so genuine extra data
	// still reports.
	test('still reports a row with more cells than the forgiveness allows', () => {
		expect(parseCSV('title,externalid,\nFoo,123,EXTRA,MORE').ragged).toEqual([
			{ line: 2, cells: 4, expected: 2 }
		]);
	});

	// Dropping a middle empty header would shift every column after it.
	test('keeps an empty header in the middle, so misalignment still reports', () => {
		const { rows } = parseCSV('title,,externalid\nFoo,mid,123');
		expect(rows).toEqual([{ title: 'Foo', '': 'mid', externalid: '123' }]);
	});
});

describe('parseCSV acceptance', () => {
	// One record shaped the way a real reviewing-platform export is: a BOM, CRLF
	// endings, a title wrapped across two lines, a multi-line status field, and a
	// trailing comma on the header.
	test('reads a realistic export as a single clean record', () => {
		const csv =
			'﻿"Manuscript ID","Manuscript Title","Status",\r\n' +
			'"X-2025-0053.R1","Flexible Deadlines:\r\nA Systematic Review",' +
			'"AE: Petersen, Andrew\r\nEIC: Ko, Amy\r\n3 invited; 0 agreed\r\n"\r\n';
		const { rows, ragged } = parseCSV(csv);
		expect(ragged).toEqual([]);
		expect(rows).toEqual([
			{
				'Manuscript ID': 'X-2025-0053.R1',
				'Manuscript Title': 'Flexible Deadlines:\nA Systematic Review',
				Status: 'AE: Petersen, Andrew\nEIC: Ko, Amy\n3 invited; 0 agreed'
			}
		]);
	});
});
