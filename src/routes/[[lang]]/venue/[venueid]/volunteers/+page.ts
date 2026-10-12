import isVenueApprover from '#lib/data/isVenueApprover.js';
import { NO_VENUE_ID } from '#lib/data/venuePath.js';
import type { PageLoad } from './$types.js';

export const load: PageLoad = async ({ parent }) => {
	// The venue comes from the layout rather than being fetched again here: the layout is
	// what resolves a web address to a venue, and refetching by the URL segment would look
	// up an address in an id column.
	const { db, venue, scholar } = await parent();

	const venueid = venue?.id ?? NO_VENUE_ID;

	// The commitments to the venue's roles. RLS returns only the ones this viewer may
	// see: a role can publish all of its volunteers, only those who have completed work
	// at the venue, or none of them.
	const { data: commitments } = await db.getVenueCommitments(venueid);

	const { data: roles } = await db.getVenueRoles(venueid);

	// How many volunteers each role really has, which stays public whatever the roster
	// says. Without it the page cannot tell a role nobody has volunteered for from one
	// whose roster is withheld, and would report the second as the first.
	const { data: volunteerCounts } = await db.getVenueVolunteerCounts(venueid);

	// Whether the viewer may see volunteers' addresses: those who assign others need to
	// reach a volunteer who has not bid. Accepted records rather than active ones, since
	// an editor who has paused taking new work still handles the papers they have.
	const { data: viewerVolunteering } =
		scholar === null || roles === null || roles.length === 0
			? { data: null }
			: await db.getScholarAcceptedVolunteering(
					scholar.id,
					roles.map((r) => r.id)
				);
	const canContact = isVenueApprover(
		venue,
		roles ?? [],
		viewerVolunteering ?? [],
		scholar?.id ?? null
	);

	return {
		venue,
		canContact,
		commitments,
		roles,
		volunteerCounts
	};
};
