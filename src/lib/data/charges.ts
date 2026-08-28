import { ORCIDRegex } from './ORCID';
import type { Charge } from './CRUD';

/** Validation for the per-author charges on a new submission.
 *
 * These are the client half of a rule the database now also enforces: since
 * migration 20260816000000, `create_submission` rejects payments that don't sum
 * to the submission type's cost (RR007) and any author listed twice (RR008).
 * These functions exist so the form can say so before the round trip, not
 * instead of the database saying so. */

/** A charge row the author has actually filled in. The form starts with one
 * blank row and payment-free venues submit with blank rows left in place, so
 * every rule below has to ignore them rather than treat them as data. */
function filled(charges: Charge[]): Charge[] {
	return charges.filter((charge) => charge.scholar.trim() !== '');
}

/** Every named author has a well-formed ORCID and a real payment amount. */
export function validChargeFormat(charges: Charge[]): boolean {
	const rows = filled(charges);
	return (
		rows.length === 0 ||
		rows.every(
			(charge) =>
				ORCIDRegex.test(charge.scholar.trim()) &&
				charge.payment !== undefined &&
				!isNaN(charge.payment)
		)
	);
}

/** The charges add up to exactly the submission type's cost. */
export function validCharge(charges: Charge[], cost: number): boolean {
	const rows = filled(charges);
	return rows.length === 0 || rows.reduce((sum, charge) => sum + (charge.payment ?? 0), 0) === cost;
}

/** True when the same scholar appears more than once.
 *
 * Blank rows are excluded first: two untouched author rows are not a duplicate,
 * and treating them as one made this unusable as a submit gate — which is part
 * of why it was only ever wired to a warning.
 *
 * The comparison is case-insensitive because an ORCID's final character may be
 * an X, and `…-123X` and `…-123x` name the same person. The database would
 * reject the pair anyway (RR008 compares resolved scholar ids), so matching
 * case-insensitively here keeps the form's answer the same as the server's
 * rather than letting the form wave through what the server will refuse. */
export function duplicateScholars(charges: Charge[]): boolean {
	const scholars = filled(charges).map((charge) => charge.scholar.trim().toLowerCase());
	return new Set(scholars).size !== scholars.length;
}

/** The whole charge list is submittable: correctly formed, summing to cost, and
 * naming no one twice. A zero cost still has to pass the format and duplicate
 * checks, because a payment-free venue can still list its authors wrongly. */
export function validCharges(charges: Charge[], cost: number): boolean {
	if (duplicateScholars(charges)) return false;
	if (!validChargeFormat(charges)) return false;
	return cost === 0 || validCharge(charges, cost);
}
