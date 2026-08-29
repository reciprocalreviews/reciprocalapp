import { NO_VENUE_ID } from '$lib/data/venuePath';
import type { PageLoad } from './$types.js';

export const load: PageLoad = async ({ parent, params }) => {
	const { db, venue } = await parent();

	// The URL segment may be the venue's web address, so the id comes from the venue the
	// layout resolved, never from the param — every query below is keyed on a uuid column.
	const venueid = venue?.id ?? NO_VENUE_ID;

	const { data: submissionTypes } = await db.getVenueSubmissionTypes(venueid);

	const { data: existingSubmissions } = await db.getVenueSubmissionExternalIDs(venueid);

	return {
		venue,
		submissionTypes,
		existingExternalIDs: (existingSubmissions ?? []).map((s) => s.externalid)
	};
};
