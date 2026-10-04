import { NO_VENUE_ID } from '#lib/data/venuePath.js';
import type { PageLoad } from './$types.js';

export const load: PageLoad = async ({ parent }) => {
	const { db, scholar, venue } = await parent();

	// The URL segment may be the venue's web address, so the id comes from the venue the
	// layout resolved, never from the param.
	const venueid = venue?.id ?? NO_VENUE_ID;

	// RLS returns only the rows this viewer could approve once matched, so this is the
	// viewer's own list rather than the venue's: an admin sees all of them, an associate
	// editor the reviewers missing from their own submissions, and a signed-out visitor
	// nothing.
	const { data: unmatched } =
		scholar === null ? { data: [] } : await db.getUnmatchedAssignments(venueid);

	// The venue's roles, and who holds them, so each name can be matched against the
	// people who could actually take the assignment.
	const { data: roles } = await db.getVenueRoles(venueid);
	const { data: commitments } =
		(unmatched ?? []).length > 0 ? await db.getVenueCommitments(venueid) : { data: [] };

	return {
		venue,
		unmatched,
		roles: roles ?? [],
		commitments: commitments ?? []
	};
};
