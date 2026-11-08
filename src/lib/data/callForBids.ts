/**
 * The rules for composing a call for bids — the short personal note a venue's editor writes
 * to the volunteers of one biddable role, asking them to come and bid.
 *
 * Kept out of the component so they can be tested without mounting one, the way
 * `volunteersView` and `inviteList` are. They are also the client half of a rule the database
 * enforces for real: `queue_call_for_bids` re-checks the same bounds, because a validation
 * that only exists in a form is a suggestion.
 */

/** The longest note the database will accept. Mirrors the bound on a thank-you note, and for
 * the same reason: this is one paragraph of somebody's prose inside branded mail, not a
 * newsletter. */
export const NOTE_LIMIT = 1000;

/** Whether a note is something the database would accept. Empty, or whitespace only, is not:
 * a call for bids with nothing in it is a branded email from a colleague that says nothing. */
export function noteIsSendable(note: string): boolean {
	const trimmed = note.trim();
	return trimmed.length > 0 && note.length <= NOTE_LIMIT;
}

/**
 * How much room is left, for the counter beside the field.
 *
 * Measured against the RAW note rather than the trimmed one, because the limit the database
 * checks is on what gets stored. A writer who is over by exactly the trailing newline they
 * cannot see should be told they are over.
 */
export function noteRemaining(note: string): number {
	return NOTE_LIMIT - note.length;
}
