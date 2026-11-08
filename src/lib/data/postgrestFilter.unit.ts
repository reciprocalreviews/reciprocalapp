import { describe, expect, test } from 'vitest';
import { eqFilter, inFilter, quoteFilterValue } from './postgrestFilter';

describe('quoteFilterValue', () => {
	test('quotes an ordinary value without otherwise touching it', () => {
		expect(quoteFilterValue('amy@uw.edu')).toBe('"amy@uw.edu"');
		expect(quoteFilterValue('0000-0001-7461-1825')).toBe('"0000-0001-7461-1825"');
	});

	test('escapes a quote, which validEmail permits in a local part', () => {
		// The case that motivates the module: unescaped, this closes the quoted value
		// early and `b@c.co` is read as filter syntax.
		expect(quoteFilterValue('a"b@c.co')).toBe('"a\\"b@c.co"');
	});

	test('escapes a backslash', () => {
		expect(quoteFilterValue('a\\b@c.co')).toBe('"a\\\\b@c.co"');
	});

	test('escapes backslashes before quotes, so the escapes do not escape each other', () => {
		// A naive quote-first pass would turn \" into \\" — a literal backslash followed
		// by an unescaped quote, which is the bug this ordering avoids.
		expect(quoteFilterValue('a\\"b')).toBe('"a\\\\\\"b"');
	});

	test('quotes the characters supabase-js quotes for, too', () => {
		expect(quoteFilterValue('a,b')).toBe('"a,b"');
		expect(quoteFilterValue('a(b)')).toBe('"a(b)"');
	});

	test('quotes an empty value rather than producing a bare comma', () => {
		expect(quoteFilterValue('')).toBe('""');
	});
});

describe('inFilter', () => {
	test('builds a comma-separated in clause', () => {
		expect(inFilter('email', ['a@x.edu', 'b@y.edu'])).toBe('email.in.("a@x.edu","b@y.edu")');
	});

	test('quotes every value, not just the suspicious ones', () => {
		expect(inFilter('email', ['a"b@c.co', 'd@e.co'])).toBe('email.in.("a\\"b@c.co","d@e.co")');
	});

	test('produces an empty clause for an empty list, which PostgREST rejects', () => {
		// Documented rather than defended against: callers guard the empty case, because
		// an empty list means there is nothing to ask about at all.
		expect(inFilter('email', [])).toBe('email.in.()');
	});
});

describe('eqFilter', () => {
	test('quotes the value', () => {
		expect(eqFilter('orcid', '0000-0001-7461-1825')).toBe('orcid.eq."0000-0001-7461-1825"');
		expect(eqFilter('email', 'a(b@c.co')).toBe('email.eq."a(b@c.co"');
	});
});
