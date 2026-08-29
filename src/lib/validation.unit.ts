import { describe, expect, test } from 'vitest';
import {
	isntEmpty,
	validEmail,
	validEmails,
	validEmailsOrORCIDs,
	validInteger,
	validORCID,
	validURL
} from './validation';

describe('validInteger', () => {
	test('accepts a plain non-negative integer', () => {
		expect(validInteger('0')).toBe(true);
		expect(validInteger('7')).toBe(true);
		expect(validInteger('120')).toBe(true);
	});

	test('rejects empty input', () => {
		expect(validInteger('')).toBe(false);
	});

	// The call sites feed the accepted text straight into parseInt() and hand the
	// result to editVenueWelcomeAmount / editSubmissionTypeCost. Anything that
	// passes here but parses to NaN writes a broken value to a `not null` column,
	// so these are correctness cases, not cosmetics.
	test('rejects text with digits buried in it, which parseInt turns into NaN', () => {
		expect(validInteger('abc12')).toBe(false);
		expect(parseInt('abc12')).toBeNaN();
	});

	test('rejects trailing junk that parseInt would silently truncate', () => {
		expect(validInteger('12abc')).toBe(false);
		expect(validInteger('1e5')).toBe(false);
	});

	// A negative welcome_amount is not rejected by the database (the column has no
	// CHECK), and volunteers.sql treats `welcome_amount <= 0` as "grant nothing",
	// so it silently disables welcome tokens instead of erroring.
	test('rejects negative numbers', () => {
		expect(validInteger('-5')).toBe(false);
	});

	test('rejects decimals rather than letting parseInt truncate them', () => {
		expect(validInteger('3.7')).toBe(false);
		expect(parseInt('3.7')).toBe(3);
	});

	test('rejects surrounding whitespace and a leading plus', () => {
		expect(validInteger(' 7 ')).toBe(false);
		expect(validInteger('+3')).toBe(false);
	});
});

describe('validEmail', () => {
	test('accepts an ordinary address', () => {
		expect(validEmail('amy@example.com')).toBe(true);
		expect(validEmail('a.b+tag@sub.example.co.uk')).toBe(true);
	});

	test('rejects text with no address in it', () => {
		expect(validEmail('')).toBe(false);
		expect(validEmail('not an email')).toBe(false);
		expect(validEmail('amy@example')).toBe(false);
	});

	// Unanchored, the pattern matched anywhere in the string, so a display name or
	// trailing prose came back valid and was then stored as the whole address.
	test('rejects an address embedded in surrounding text', () => {
		expect(validEmail('Amy Ko <a@b.co> extra')).toBe(false);
		expect(validEmail('mail me at amy@example.com please')).toBe(false);
	});

	test('rejects a whole comma-separated list, which is validEmails’ job', () => {
		expect(validEmail('a@b.co, c@d.co')).toBe(false);
	});

	// Every consumer trims before using the address, so surrounding whitespace is
	// insignificant and reporting it as invalid only blocks a save that would have
	// succeeded. Internal whitespace is a different matter and still fails, which is
	// what keeps the embedded-in-prose cases above rejected.
	test('accepts an address padded with whitespace', () => {
		expect(validEmail('  amy@example.com  ')).toBe(true);
		expect(validEmail('\tamy@example.com\n')).toBe(true);
	});
});

describe('validEmails', () => {
	test('accepts a single address and a comma-separated list with spaces', () => {
		expect(validEmails('a@b.co')).toBe(true);
		expect(validEmails('a@b.co, c@d.co')).toBe(true);
	});

	test('rejects the list when any member is malformed', () => {
		expect(validEmails('a@b.co, nope')).toBe(false);
	});

	test('rejects a trailing comma, which leaves an empty final member', () => {
		expect(validEmails('a@b.co,')).toBe(false);
	});

	test('enforces the minimum-length floor', () => {
		expect(validEmails('a@b.co', 1)).toBe(true);
		expect(validEmails('a@b.co', 2)).toBe(false);
		expect(validEmails('a@b.co, c@d.co', 2)).toBe(true);
	});

	test('rejects empty input, since splitting it yields one empty member', () => {
		expect(validEmails('')).toBe(false);
	});
});

describe('validORCID / validEmailsOrORCIDs', () => {
	test('accepts a well-formed iD, including the X check character', () => {
		expect(validORCID('0000-0001-7461-4783')).toBe(true);
		expect(validORCID('0000-0002-1825-009X')).toBe(true);
	});

	test('rejects malformed iDs', () => {
		expect(validORCID('0000-0001-7461-4783-0000')).toBe(false);
		expect(validORCID('0000-0001-7461')).toBe(false);
		expect(validORCID('')).toBe(false);
	});

	test('accepts a mixed list of addresses and iDs', () => {
		expect(validEmailsOrORCIDs('a@b.co, 0000-0001-7461-4783')).toBe(true);
	});

	test('rejects the list when a member is neither', () => {
		expect(validEmailsOrORCIDs('a@b.co, 1234')).toBe(false);
	});
});

describe('validURL', () => {
	test('accepts ordinary http(s) URLs', () => {
		expect(validURL('https://example.com')).toBe(true);
		expect(validURL('http://www.example.com')).toBe(true);
		expect(validURL('https://example.com/path?q=1&r=2#frag')).toBe(true);
		expect(validURL('https://dl.acm.org/journal/tochi')).toBe(true);
		expect(validURL('https://sub.domain.co.uk/path?a=1&b=2')).toBe(true);
	});

	// Anchoring turned the TLD length cap into a real constraint for the first
	// time. At the previous limit of 6 it rejected `.reviews` — this platform's
	// own domain, and the URL every venue's transaction template points at.
	test('accepts a long TLD, including this platform’s own domain', () => {
		expect(validURL('https://reciprocal.reviews')).toBe(true);
		expect(validURL('https://reciprocal.reviews/venue/abc')).toBe(true);
		expect(validURL('https://example.international')).toBe(true);
	});

	test('rejects text that merely contains a URL', () => {
		expect(validURL('garbage http://x.co more')).toBe(false);
		expect(validURL('see https://example.com')).toBe(false);
	});

	test('rejects non-URLs', () => {
		expect(validURL('')).toBe(false);
		expect(validURL('example.com')).toBe(false);
		expect(validURL('ftp://example.com')).toBe(false);
	});
});

describe('isntEmpty', () => {
	test('distinguishes empty from non-empty', () => {
		expect(isntEmpty('')).toBe(false);
		expect(isntEmpty('a')).toBe(true);
	});

	// Documented as-is: it is a length check, not a trim check, so a
	// whitespace-only value passes. Callers that care trim first.
	test('treats whitespace as non-empty', () => {
		expect(isntEmpty(' ')).toBe(true);
	});
});
