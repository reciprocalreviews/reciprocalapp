import { test, expect } from 'vitest';
import { dedupeAddresses, parseAddresses } from './addresses';

test('Parse a comma-separated field', () => {
	expect(parseAddresses('a@x.edu, b@x.edu')).toEqual(['a@x.edu', 'b@x.edu']);
	expect(parseAddresses('  a@x.edu ,b@x.edu  ')).toEqual(['a@x.edu', 'b@x.edu']);
	expect(parseAddresses('')).toEqual([]);
	expect(parseAddresses('a@x.edu,,')).toEqual(['a@x.edu']);
});

test('Drop repeats, keeping the order first given', () => {
	expect(parseAddresses('a@x.edu, b@x.edu, a@x.edu')).toEqual(['a@x.edu', 'b@x.edu']);
	expect(dedupeAddresses(['b@x.edu', 'a@x.edu', 'b@x.edu'])).toEqual(['b@x.edu', 'a@x.edu']);
});

test('Case is preserved, because approval matches the address exactly', () => {
	// Folding case here would change which spelling is stored, and so whether
	// approve_venue_proposal resolves it against scholars.email at all.
	expect(parseAddresses('A@x.edu, a@x.edu')).toEqual(['A@x.edu', 'a@x.edu']);
});
