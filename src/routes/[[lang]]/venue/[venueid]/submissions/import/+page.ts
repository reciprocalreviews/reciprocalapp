import type { PageLoad } from './$types.js';

export const load: PageLoad = async ({ parent, params }) => {
	const { db, venue } = await parent();

	const venueid = params.venueid;

	const { data: submissionTypes } = await db.getVenueSubmissionTypes(venueid);

	const { data: existingSubmissions } = await db.getVenueSubmissionExternalIDs(venueid);

	return {
		venue,
		submissionTypes,
		existingExternalIDs: (existingSubmissions ?? []).map((s) => s.externalid)
	};
};
