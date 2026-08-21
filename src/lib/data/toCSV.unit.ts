import { describe, expect, test } from 'vitest';
import parseCSV from './parseCSV';
import toCSV from './toCSV';

describe('toCSV', () => {
	test('writes a header and rows', () => {
		expect(toCSV(['a', 'b'], [['1', '2']])).toBe('"a","b"\n"1","2"');
	});

	test('writes a header alone when there are no rows', () => {
		expect(toCSV(['a', 'b'], [])).toBe('"a","b"');
	});

	test('quotes commas so they do not become column separators', () => {
		expect(toCSV(['name'], [['Smith, Jones and Co']])).toBe('"name"\n"Smith, Jones and Co"');
	});

	test('doubles embedded quotes', () => {
		expect(toCSV(['note'], [['He said "hi"']])).toBe('"note"\n"He said ""hi"""');
	});

	test('preserves empty cells', () => {
		expect(toCSV(['a', 'b'], [['', 'x']])).toBe('"a","b"\n"","x"');
	});
});

describe('toCSV round trip', () => {
	// The pair is only useful if it is actually lossless, and the characters that
	// break naive CSV are exactly the ones a scholar's name or expertise contains.
	test('survives commas, quotes and the # that used to truncate the download', () => {
		const headers = ['Name', 'Email', 'Expertise'];
		const rows = [
			['Ko, Amy', 'amy@example.com', 'C# and F#'],
			['He said "hi"', 'b@example.com', 'HCI, SE'],
			['Plain', 'c@example.com', '']
		];
		const parsed = parseCSV(toCSV(headers, rows));
		expect(parsed.ragged).toEqual([]);
		expect(parsed.rows).toEqual([
			{ Name: 'Ko, Amy', Email: 'amy@example.com', Expertise: 'C# and F#' },
			{ Name: 'He said "hi"', Email: 'b@example.com', Expertise: 'HCI, SE' },
			{ Name: 'Plain', Email: 'c@example.com', Expertise: '' }
		]);
	});
});
