import type { LayoutLoad } from './$types.js';

export const load: LayoutLoad = async ({ parent, params }) => {
	const { db } = await parent();

	const venueid = params.venueid;

	// Get the matching venue.
	const { data: venue } = await db.getVenue(venueid);

	return {
		venue
	};
};
