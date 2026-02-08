import { test, expect } from 'vitest';
import { ORCIDRegex } from './ORCID';

test('Check ORCIDs', () => {
	expect(ORCIDRegex.test('0000-0001-7461-4783')).toBe(true);
	expect(ORCIDRegex.test('0000-0001-7461-4783-0000')).toBe(false);
});
