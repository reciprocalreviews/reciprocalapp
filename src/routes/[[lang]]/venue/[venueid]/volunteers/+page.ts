import { NO_VENUE_ID } from '$lib/data/venuePath';
import type { PageLoad } from './$types.js';

export const load: PageLoad = async ({ parent }) => {
	// The venue comes from the layout rather than being fetched again here: the layout is
	// what resolves a web address to a venue, and refetching by the URL segment would look
	// up an address in an id column.
	const { db, venue } = await parent();

	const venueid = venue?.id ?? NO_VENUE_ID;

	// The commitments to the venue's roles.
	const { data: commitments } = await db.getVenueCommitments(venueid);

	const { data: roles } = await db.getVenueRoles(venueid);

	return {
		venue,
		commitments,
		roles
	};
};
