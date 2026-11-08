/**
 * Email addresses are collected as one comma-separated field on the venue proposal form and
 * stored as a `text[]`. Two things have to be true of that array and neither is free: entries
 * are trimmed, and no address appears twice.
 *
 * Duplicates are not harmless. `queue_email('ProposalCreatedEditors')` sends one message per
 * listed address, so a double-listed editor is invited twice; and `approve_venue_proposal`
 * resolves the list against `scholars`, where one scholar comes back for two identical entries.
 *
 * De-duplication is exact rather than case-insensitive on purpose: approval matches
 * `scholars.email` exactly, so folding case here would silently change which spelling is stored
 * and therefore whether it resolves at all.
 */

/** Split a comma-separated field into trimmed, de-duplicated, non-empty addresses. */
export function parseAddresses(text: string): string[] {
	return dedupeAddresses(text.split(','));
}

/** Trim, drop empties, and remove repeats, preserving the order first given. */
export function dedupeAddresses(addresses: string[]): string[] {
	return [...new Set(addresses.map((address) => address.trim()).filter((a) => a.length > 0))];
}
