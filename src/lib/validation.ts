import { ORCIDRegex } from './data/ORCID';

/** Anchored, and excluding whitespace and commas on both sides of the `@`.
 * Anchoring alone is not enough: `^.+@.+\..+$` still matches "Amy Ko <a@b.co>
 * extra", because `.` matches the spaces. Commas are excluded so that a whole
 * list fails here and is only accepted by validEmails, which splits first.
 *
 * Surrounding whitespace is trimmed first, because everything that consumes an
 * address already trims it — request_email_verification, VerifyEmail.request(),
 * validEmails and validEmailsOrORCIDs all do — so a pasted address with a stray
 * space around it is a valid address, not a mistake to report. Internal
 * whitespace is still rejected, so the embedded-in-prose cases above still fail. */
export function validEmail(text: string) {
	return /^[^\s,@]+@[^\s,@]+\.[^\s,@]+$/.test(text.trim());
}

export function validORCID(id: string) {
	return ORCIDRegex.test(id);
}

export function validEmails(text: string, length = 0) {
	const list = text.split(',').map((email) => email.trim());
	return list.every((email) => validEmail(email)) && list.length >= length;
}

export function validEmailsOrORCIDs(text: string) {
	return text
		.split(',')
		.map((id) => id.trim())
		.every((id) => validEmail(id) || validORCID(id));
}

export function isntEmpty(text: string) {
	return text.length > 0;
}

/** Anchored, so the field must BE a URL rather than merely contain one —
 * unanchored, "garbage http://x.co more" validated and was then stored whole as
 * a venue's link.
 *
 * The TLD allows up to 24 characters rather than the 6 this pattern used to
 * assume. Long TLDs are ordinary now, and while the pattern was unanchored the
 * limit did no harm — a match on the first six letters of `.reviews` was still a
 * match, so `https://reciprocal.reviews` passed on a partial. Anchoring makes
 * the length a real constraint, and the first thing it would have rejected is
 * this platform's own domain. */
export function validURL(text: string) {
	return /^https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{2,24}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)$/.test(
		text
	);
}

/** Anchored and non-negative. Callers pass the accepted text to parseInt() and
 * write the result to `not null` integer columns (venue welcome amount,
 * submission cost), so an unanchored `[0-9]+` was actively harmful: "abc12"
 * validated and parsed to NaN, and "-5" validated and produced a negative
 * welcome_amount, which volunteers.sql reads as "grant nothing". */
export function validInteger(text: string) {
	return /^\d+$/.test(text);
}
