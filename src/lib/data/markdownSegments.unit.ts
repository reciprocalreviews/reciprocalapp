import { describe, expect, test } from 'vitest';
import markdownToSegments from './markdownSegments';

describe('markdownToSegments', () => {
	test('returns plain text as a single segment', () => {
		expect(markdownToSegments('Just words.')).toEqual(['Just words.']);
	});

	test('returns nothing for an empty string', () => {
		expect(markdownToSegments('')).toEqual([]);
	});

	test('recognizes an issue reference', () => {
		expect(markdownToSegments('Fixed (#123)')).toEqual(['Fixed ', { type: 'issue', text: '123' }]);
	});

	test('recognizes code, bold and italic', () => {
		expect(markdownToSegments('`a`')).toEqual([{ type: 'code', text: 'a' }]);
		expect(markdownToSegments('**a**')).toEqual([{ type: 'bold', text: 'a' }]);
		expect(markdownToSegments('*a*')).toEqual([{ type: 'italic', text: 'a' }]);
	});

	// Bold must win over italic, since `**a**` also matches the italic pattern.
	test('prefers bold over italic for doubled asterisks', () => {
		expect(markdownToSegments('**bold**')).toEqual([{ type: 'bold', text: 'bold' }]);
	});

	test('recognizes a link and keeps its target', () => {
		expect(markdownToSegments('[docs](https://example.com)')).toEqual([
			{ type: 'link', text: 'docs', link: 'https://example.com' }
		]);
	});

	// The cursor arithmetic: text before, between and after matches must all
	// survive, with no character dropped or repeated at a boundary.
	test('keeps the text around and between matches', () => {
		expect(markdownToSegments('a `b` c **d** e')).toEqual([
			'a ',
			{ type: 'code', text: 'b' },
			' c ',
			{ type: 'bold', text: 'd' },
			' e'
		]);
	});

	test('keeps trailing text after the last match', () => {
		expect(markdownToSegments('`a` tail')).toEqual([{ type: 'code', text: 'a' }, ' tail']);
	});

	test('emits no empty string between adjacent matches', () => {
		expect(markdownToSegments('`a``b`')).toEqual([
			{ type: 'code', text: 'a' },
			{ type: 'code', text: 'b' }
		]);
	});

	test('round-trips the visible characters of a mixed line', () => {
		const source = 'Fixed `parseCSV` (#42) and [docs](https://x.co) — see **notes**.';
		const visible = markdownToSegments(source)
			.map((s) => (typeof s === 'string' ? s : s.text))
			.join('');
		expect(visible).toBe('Fixed parseCSV 42 and docs — see notes.');
	});

	// A shared global regex would carry lastIndex between calls and make the
	// second call start mid-string.
	test('is not affected by the previous call', () => {
		const input = 'a `b` c';
		expect(markdownToSegments(input)).toEqual(markdownToSegments(input));
	});

	test('leaves unmatched markers alone', () => {
		expect(markdownToSegments('a * b')).toEqual(['a * b']);
		expect(markdownToSegments('(#abc)')).toEqual(['(#abc)']);
	});
});
