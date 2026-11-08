/**
 * The path segment a venue is reached by.
 *
 * A venue chooses a web address during setup and is addressed by it from then on. Until
 * it has one — and every venue that predates the feature is in that state — its id stands
 * in, so nothing has to wait for a name to have a URL.
 *
 * Both forms resolve (`getVenueByPath`), and the venue layout redirects the id form to the
 * address, so a link built here from an id is never wrong, only unlovely. That is what
 * makes it safe to adopt this gradually: the places holding a whole venue row use it now,
 * and the places holding a bare id keep working meanwhile.
 */
export function venuePath(venue: { id: string; slug: string | null }): string {
	return venue.slug ?? venue.id;
}

/**
 * The id to query with when no venue resolved.
 *
 * The venue layout renders an "unknown venue" page in that case, but its child loads still
 * run, and every one of them keys a query on a uuid column. An empty string is not a uuid,
 * so Postgres rejects it with `22P02` and each load reports a failure for a page that is
 * only saying the venue isn't there. The nil uuid is well-formed and matches nothing —
 * `gen_random_uuid()` never produces it — so those queries come back empty, quietly, which
 * is the truth.
 */
export const NO_VENUE_ID = '00000000-0000-0000-0000-000000000000';
