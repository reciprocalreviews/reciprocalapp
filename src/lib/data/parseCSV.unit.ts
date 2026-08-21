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
