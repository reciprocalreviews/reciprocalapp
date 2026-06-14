import type { PageLoad } from './$types.js';

export const load: PageLoad = async ({ parent, params }) => {
	const { db } = await parent();

	const venueid = params.venueid;

	// Get the matching venue.
	const { data: venue } = await db.getVenue(venueid);

	// The commitments to the venue's roles.
	const { data: commitments } = await db.getVenueCommitments(venueid);

	const { data: roles } = await db.getVenueRoles(venueid);

	return {
		venue,
		commitments,
		roles
	};
};
