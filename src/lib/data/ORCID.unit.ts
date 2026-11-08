import { test, expect } from 'vitest';
import { ORCIDRegex, orcidURL } from './ORCID';

test('Check ORCIDs', () => {
	expect(ORCIDRegex.test('0000-0001-7461-4783')).toBe(true);
	expect(ORCIDRegex.test('0000-0001-7461-4783-0000')).toBe(false);
});

test('Build a profile URL from an ORCID', () => {
	expect(orcidURL('0000-0001-7461-4783')).toBe('https://orcid.org/0000-0001-7461-4783');
	// An iD ending in the checksum character X is still just the path.
	expect(orcidURL('0000-0002-1825-009X')).toBe('https://orcid.org/0000-0002-1825-009X');
});
