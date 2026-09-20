import { describe, expect, test } from 'vitest';
import { fits, type Fit } from './fit';

/** A row 300 wide with nothing else in it, a 20-wide control and a 10 gap. */
function row(overrides: Partial<Fit> = {}): Fit {
	return { available: 300, base: 0, widths: [], toggle: 20, gap: 10, ...overrides };
}

describe('fits', () => {
	test('keeps everything when everything fits', () => {
		// 3 * (50 + 10) = 180, well under 300.
		expect(fits(row({ widths: [50, 50, 50] }))).toBe(3);
	});

	test('does not charge for the control when nothing is collapsed', () => {
		// 290 of items exactly fills 300 only because the control is not charged. Charging
		// it would cost an item, and that item would then be behind a control that exists
		// solely because it left — the off-by-one this function is split in two to avoid.
		expect(fits(row({ widths: [140, 140], gap: 5 }))).toBe(2);
	});

	test('charges for the control as soon as anything is collapsed', () => {
		// One pixel over: 3 * (95 + 5) = 300 fits, 3 * (96 + 5) = 303 does not. Once it
		// does not, the control costs 25 more, so only two survive.
		expect(fits(row({ widths: [95, 95, 95], gap: 5 }))).toBe(3);
		expect(fits(row({ widths: [96, 96, 96], gap: 5 }))).toBe(2);
	});

	test('collapses from the end, not by size', () => {
		// One wide item first and three narrow ones after it, in a row with room for about
		// one of them. A policy that gave up the most expensive item would keep the three
		// narrow ones; this keeps the wide one, because order is priority and the row
		// collapses from the end. That is the contract `venueBarLinks` relies on.
		expect(fits(row({ available: 250, widths: [200, 30, 30, 30], gap: 5 }))).toBe(1);
	});

	test('counts what the rest of the row already needs', () => {
		// The same items, once with a breadcrumb and a balance in the row and once without.
		expect(fits(row({ base: 0, widths: [80, 80, 80], gap: 5 }))).toBe(3);
		expect(fits(row({ base: 200, widths: [80, 80, 80], gap: 5 }))).toBe(0);
	});

	test('gives up everything when not even the control fits beside the rest', () => {
		expect(fits(row({ base: 295, widths: [50], gap: 5 }))).toBe(0);
	});

	test('an empty menu never makes the row wider', () => {
		// No items means nothing to collapse, so the control must not be charged for —
		// otherwise an empty overflow would cost a row 20px of nothing.
		expect(fits(row({ base: 295, widths: [] }))).toBe(0);
		expect(fits(row({ base: 0, widths: [] }))).toBe(0);
	});

	test('tolerates a fractional overshoot', () => {
		// Sub-pixel widths are the normal case with proportional type; a row over by a
		// rounding error is not one anybody can see.
		expect(fits(row({ available: 300, widths: [145.2, 145.2], gap: 4.8 }))).toBe(2);
	});
});
