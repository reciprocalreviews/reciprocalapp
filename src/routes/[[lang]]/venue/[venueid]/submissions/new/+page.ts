import { NO_VENUE_ID } from '$lib/data/venuePath';
import type { PageLoad } from './$types.js';

export const load: PageLoad = async ({ parent, params }) => {
	const { db, venue, scholar } = await parent();

	// The URL segment may be the venue's web address, so the id comes from the venue the
	// layout resolved, never from the param — every query below is keyed on a uuid column.
	const venueid = venue?.id ?? NO_VENUE_ID;

	// Find all of the submissions types for the venue.
	const { data: submissionTypes } = await db.getVenueSubmissionTypes(venueid);

	// Find the submissions in this venue the authenticated scholar authored, so
	// they can link a new submission to an on-platform predecessor (#124).
	const { data: priorSubmissions } = scholar?.id
		? await db.getScholarPriorSubmissions(venueid, scholar.id)
		: { data: [] };

	return {
		venue,
		submissionTypes,
		priorSubmissions: priorSubmissions ?? [],
		// The submitter's own ORCID, so the form can list them as an author
		// rather than making them type an identifier they may not have memorized.
		scholarORCID: scholar?.orcid ?? null
	};
};
