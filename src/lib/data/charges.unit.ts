import { describe, expect, test } from 'vitest';
import { duplicateScholars, validCharge, validCharges, validChargeFormat } from './charges';

const A = '0000-0001-7461-4783';
const B = '0000-0002-1825-009X';
const BLANK = { scholar: '', payment: 0 };

describe('validChargeFormat', () => {
	test('accepts well-formed ORCIDs with numeric payments', () => {
		expect(validChargeFormat([{ scholar: A, payment: 5 }])).toBe(true);
	});

	test('rejects a malformed ORCID', () => {
		expect(validChargeFormat([{ scholar: 'not-an-orcid', payment: 5 }])).toBe(false);
	});

	// Charge.payment is `number | undefined`, and isNaN(undefined) is true, so the
	// old check let an unset payment through as "not NaN".
	test('rejects an unset payment', () => {
		expect(validChargeFormat([{ scholar: A, payment: undefined }])).toBe(false);
	});

	test('ignores blank rows', () => {
		expect(validChargeFormat([BLANK])).toBe(true);
		expect(validChargeFormat([{ scholar: A, payment: 1 }, BLANK])).toBe(true);
	});
});

describe('validCharge', () => {
	test('accepts charges that sum to the cost', () => {
		expect(validCharge([{ scholar: A, payment: 10 }], 10)).toBe(true);
		expect(
			validCharge(
				[
					{ scholar: A, payment: 6 },
					{ scholar: B, payment: 4 }
				],
				10
			)
		).toBe(true);
	});

	test('rejects underpayment and overpayment alike', () => {
		expect(validCharge([{ scholar: A, payment: 9 }], 10)).toBe(false);
		expect(validCharge([{ scholar: A, payment: 11 }], 10)).toBe(false);
	});

	test('allows a zero-charge co-author as long as the total is right', () => {
		expect(
			validCharge(
				[
					{ scholar: A, payment: 10 },
					{ scholar: B, payment: 0 }
				],
				10
			)
		).toBe(true);
	});

	test('ignores blank rows when summing', () => {
		expect(validCharge([{ scholar: A, payment: 10 }, BLANK], 10)).toBe(true);
	});
});

describe('duplicateScholars', () => {
	test('detects the same scholar listed twice', () => {
		expect(
			duplicateScholars([
				{ scholar: A, payment: 5 },
				{ scholar: A, payment: 5 }
			])
		).toBe(true);
	});

	test('accepts distinct scholars', () => {
		expect(
			duplicateScholars([
				{ scholar: A, payment: 5 },
				{ scholar: B, payment: 5 }
			])
		).toBe(false);
	});

	// The reason this was never usable as a submit gate: the form starts with one
	// blank row, and a payment-free venue submits with blank rows still present.
	test('does not treat two blank rows as a duplicate', () => {
		expect(duplicateScholars([BLANK, BLANK])).toBe(false);
	});

	test('ignores whitespace differences around the same iD', () => {
		expect(
			duplicateScholars([
				{ scholar: A, payment: 5 },
				{ scholar: ` ${A} `, payment: 5 }
			])
		).toBe(true);
	});

	// An ORCID's final character can be an X, so the same person can be typed two
	// ways. The database resolves both to one scholar id and rejects the pair
	// (RR008); the form has to agree, or it waves through what the server refuses.
	test('ignores case differences in an iD ending in X', () => {
		expect(
			duplicateScholars([
				{ scholar: B, payment: 5 },
				{ scholar: B.toLowerCase(), payment: 5 }
			])
		).toBe(true);
	});
});

describe('validCharges', () => {
	test('accepts a correct single charge', () => {
		expect(validCharges([{ scholar: A, payment: 10 }], 10)).toBe(true);
	});

	test('rejects a duplicated author even when the total is right', () => {
		expect(
			validCharges(
				[
					{ scholar: A, payment: 5 },
					{ scholar: A, payment: 5 }
				],
				10
			)
		).toBe(false);
	});

	// A zero cost skips the sum check but must not skip the others: a payment-free
	// venue can still list the same author twice or a malformed iD.
	test('still rejects duplicates and bad iDs at zero cost', () => {
		expect(
			validCharges(
				[
					{ scholar: A, payment: 0 },
					{ scholar: A, payment: 0 }
				],
				0
			)
		).toBe(false);
		expect(validCharges([{ scholar: 'nope', payment: 0 }], 0)).toBe(false);
	});

	test('accepts an authorless payment-free submission', () => {
		expect(validCharges([BLANK], 0)).toBe(true);
	});

	test('rejects a mismatched total', () => {
		expect(validCharges([{ scholar: A, payment: 3 }], 10)).toBe(false);
	});
});
