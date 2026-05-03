import { describe, expect, test } from 'vitest';
import parseCSV from './parseCSV';

describe('parseCSV', () => {
	test('returns empty array when only header is present', () => {
		expect(parseCSV('a,b,c')).toEqual([]);
	});

	test('returns empty array for empty input', () => {
		expect(parseCSV('')).toEqual([]);
	});

	test('parses a basic header + row', () => {
		expect(parseCSV('title,externalid\nFoo,123')).toEqual([{ title: 'Foo', externalid: '123' }]);
	});

	test('handles CRLF line endings', () => {
		expect(parseCSV('title,externalid\r\nFoo,123\r\nBar,456')).toEqual([
			{ title: 'Foo', externalid: '123' },
			{ title: 'Bar', externalid: '456' }
		]);
	});

	test('skips blank lines', () => {
		expect(parseCSV('title,externalid\n\nFoo,123\n\n')).toEqual([
			{ title: 'Foo', externalid: '123' }
		]);
	});

	test('handles quoted fields with commas', () => {
		expect(parseCSV('title,note\n"Foo, the bar","hello, world"')).toEqual([
			{ title: 'Foo, the bar', note: 'hello, world' }
		]);
	});

	test('handles escaped quotes inside quoted fields', () => {
		expect(parseCSV('title,note\n"He said ""hi""","quoted ""text"" here"')).toEqual([
			{ title: 'He said "hi"', note: 'quoted "text" here' }
		]);
	});

	test('trims header and cell whitespace', () => {
		expect(parseCSV(' title , externalid \n  Foo  ,  123  ')).toEqual([
			{ title: 'Foo', externalid: '123' }
		]);
	});

	test('fills missing trailing cells with empty strings', () => {
		expect(parseCSV('title,externalid,note\nFoo,123')).toEqual([
			{ title: 'Foo', externalid: '123', note: '' }
		]);
	});
});
