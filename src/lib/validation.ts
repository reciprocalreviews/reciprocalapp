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

/** The shape of a UUID, so a path segment can be told from an id without a database
 * round trip. Venue routes accept either — an id keeps working after a venue names
 * itself — and the resolver picks a column by looking. */
export function isUUID(text: string) {
	return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(text.trim());
}

/** A venue's web address: the path segment it is reached by, in place of its id.
 *
 * Four characters minimum, because three-letter acronyms are the ones most likely to be
 * contested — "CHI", "SIG", "TOK" — and handing the first arrival a name a dozen
 * communities have equal claim to is not a race worth running. Lowercase only, so an
 * address is the same address however it is typed. Hyphens between segments but never
 * leading, trailing, or doubled, and a leading letter, so an address can't be mistaken
 * for a number or read as punctuation.
 *
 * The UUID exclusion is what keeps `isUUID` above decisive: `[a-z][a-z0-9-]*` alone
 * admits `abcdef12-3456-7890-abcd-ef1234567890`, and a venue reachable by a segment that
 * could equally be an id is a venue whose URL means two things.
 *
 * Kept in step with the `venues_slug_check` constraint in supabase/schemas/venues.sql —
 * that constraint, not this function, is what actually holds.
 */
export function validVenueSlug(text: string) {
	return (
		/^[a-z][a-z0-9]*(-[a-z0-9]+)*$/.test(text) &&
		text.length >= 4 &&
		text.length <= 40 &&
		!isUUID(text)
	);
}

/** Propose a web address from a venue's title, so an admin starts from something rather
 * than a blank field. Best effort: what comes back may still be invalid (a title of "AI"
 * has no four-character address in it), and the field validates it like anything typed. */
export function slugifyTitle(title: string) {
	return title
		.toLowerCase()
		.normalize('NFD')
		.replace(/[\u0300-\u036f]/g, '')
		.replace(/[^a-z0-9]+/g, '-')
		.replace(/^-+|-+$/g, '')
		.replace(/^[0-9]+/, '')
		.replace(/^-+/, '')
		.slice(0, 40)
		.replace(/-+$/, '');
}
