// How an expertise field -- a volunteer's for a role, or a submission's -- becomes keywords.
//
// The volunteers roster shows these as chips. The weekly bidding digest matches on the same
// rule in SQL (private.expertise_keys in supabase/schemas/bidding_digests.sql), and
// supabase/tests/rpc/bidding_digest.sql holds the two to the same cases, so a keyword the email
// says matched is a chip on that page.
//
// Beside the edge functions only so the rule has one home that both runtimes could read, and
// import-free like every module in _shared. Re-exported from src/lib/data/expertise.ts.

/** An expertise field as keywords: split on commas, trimmed, empties dropped. */
export function expertiseTags(expertise: string | null | undefined): string[] {
	return (expertise ?? '')
		.split(',')
		.map((tag) => tag.trim())
		.filter((tag) => tag.length > 0);
}

/** Case is a spelling difference, not a different expertise. */
export function expertiseKey(tag: string): string {
	return tag.toLowerCase();
}
