import { NO_VENUE_ID } from '#lib/data/venuePath.js';
import type { PageLoad } from './$types.js';

export const load: PageLoad = async ({ parent }) => {
	const { db, scholar, venue } = await parent();

	// The URL segment may be the venue's web address, so the id comes from the venue the
	// layout resolved, never from the param.
	const venueid = venue?.id ?? NO_VENUE_ID;

	const { data: roles } = await db.getVenueRoles(venueid);

	// The same people who may import, by the same test (see the import page's loader):
	// admins and anyone who has accepted a priority-0 role. assign_submissions re-checks.
	const isAdmin = scholar !== null && venue !== null && venue.admins.includes(scholar.id);
	const editorRoleIDs = (roles ?? []).filter((r) => r.priority === 0).map((r) => r.id);
	const { data: editorVolunteering } =
		scholar === null || isAdmin || editorRoleIDs.length === 0
			? { data: [] }
			: await db.getScholarAcceptedVolunteering(scholar.id, editorRoleIDs);
	const mayAssign = isAdmin || (editorVolunteering ?? []).length > 0;

	// Who a name may refer to: each role's accepted, active volunteers. Not read for
	// somebody who will only be told they can't use the page.
	const { data: commitments } = mayAssign ? await db.getVenueCommitments(venueid) : { data: [] };

	return {
		venue,
		roles: roles ?? [],
		commitments: commitments ?? [],
		mayAssign
	};
};
