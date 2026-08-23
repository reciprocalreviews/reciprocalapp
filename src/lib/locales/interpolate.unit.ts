import { describe, expect, test } from 'vitest';
import { html } from './html';
import interpolate from './interpolate';

const SHORTHAND = { delete: '✖', admin: 'Admin' };

describe('interpolate', () => {
	test('returns a plain string untouched', () => {
		expect(interpolate('Nothing to do here.', SHORTHAND)).toBe('Nothing to do here.');
	});

	test('joins an array of paragraphs with a blank line', () => {
		expect(interpolate(['One.', 'Two.'], SHORTHAND)).toBe('One.\n\nTwo.');
	});

	test('substitutes a known shorthand', () => {
		expect(interpolate('Press $delete to remove.', SHORTHAND)).toBe('Press ✖ to remove.');
	});

	test('substitutes every occurrence, not just the first', () => {
		expect(interpolate('$admin and $admin', SHORTHAND)).toBe('Admin and Admin');
	});

	test('substitutes a known input', () => {
		expect(interpolate('Check line {lines}.', SHORTHAND, { lines: '2, 4' })).toBe(
			'Check line 2, 4.'
		);
	});

	test('handles shorthand and inputs in the same string', () => {
		expect(interpolate('$admin {name} may edit.', SHORTHAND, { name: 'Amy' })).toBe(
			'Admin Amy may edit.'
		);
	});

	// Leaving the placeholder visible is the point: a hole in a sentence is
	// harder to notice than a literal `$typo`.
	test('leaves an unknown shorthand as written', () => {
		expect(interpolate('A $mystery here.', SHORTHAND)).toBe('A $mystery here.');
	});

	test('leaves an unknown input as written', () => {
		expect(interpolate('A {mystery} here.', SHORTHAND)).toBe('A {mystery} here.');
	});

	test('never renders the word undefined', () => {
		expect(interpolate('$nope {nope}', SHORTHAND, {})).not.toContain('undefined');
	});

	test('treats an empty inputs object as no inputs', () => {
		expect(interpolate('{a}', SHORTHAND)).toBe('{a}');
	});

	// The shorthand pass runs first, so a shorthand whose VALUE contains braces
	// could be re-read by the input pass. Documented rather than guarded: no
	// shorthand does this today, and a test will catch it if one starts.
	test('applies inputs after shorthand', () => {
		expect(interpolate('$brace', { brace: '{name}' }, { name: 'Amy' })).toBe('Amy');
	});

	test('does not treat a lone dollar or brace as a placeholder', () => {
		expect(interpolate('100$ and { }', SHORTHAND)).toBe('100$ and { }');
	});

	test('does not rescan a substituted input', () => {
		// tokenChip injects markup as an input value; nothing in it may be re-read,
		// or a currency name containing `{cost}` could pull in another input.
		expect(interpolate('{a} {b}', SHORTHAND, { a: '<i>{b} $admin</i>', b: 'B' })).toBe(
			'<i>{b} $admin</i> B'
		);
	});
});

// The `escape` pass is what stands between a venue-authored description and
// `{@html}`. See the comment in interpolate.ts.
describe('interpolate escaping', () => {
	test('leaves inputs alone when the result is not going through @html', () => {
		expect(interpolate('{x}', SHORTHAND, { x: '<b>hi</b>' })).toBe('<b>hi</b>');
	});

	test('escapes an input when the result is going through @html', () => {
		expect(interpolate('{x}', SHORTHAND, { x: '<b>hi</b>' }, true)).toBe('&lt;b&gt;hi&lt;/b&gt;');
	});

	test('defuses the stored-XSS shape this was written for', () => {
		const escaped = interpolate(
			'{description}',
			SHORTHAND,
			{ description: '<img src=x onerror=alert(1)>' },
			true
		);
		expect(escaped).not.toContain('<img');
	});

	test('escapes quotes and ampersands, not just angle brackets', () => {
		expect(interpolate('{x}', SHORTHAND, { x: `&"'` }, true)).toBe('&amp;&quot;&#39;');
	});

	test('passes an explicitly trusted value through unescaped', () => {
		expect(interpolate('{x}', SHORTHAND, { x: html('<b>hi</b>') }, true)).toBe('<b>hi</b>');
	});

	test('does not escape shorthand, which is authored in the locale file', () => {
		expect(interpolate('$delete', { delete: '<b>x</b>' }, {}, true)).toBe('<b>x</b>');
	});

	test('markdown in an escaped input still works, since only markup is neutralized', () => {
		expect(interpolate('{x}', SHORTHAND, { x: '**bold**' }, true)).toBe('**bold**');
	});
});
