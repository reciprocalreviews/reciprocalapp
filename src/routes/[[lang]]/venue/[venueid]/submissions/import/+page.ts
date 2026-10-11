import { NO_VENUE_ID } from '#lib/data/venuePath.js';
import type { PageLoad } from './$types.js';

export const load: PageLoad = async ({ parent, params }) => {
	const { db, scholar, venue } = await parent();

	// The URL segment may be the venue's web address, so the id comes from the venue the
	// layout resolved, never from the param — every query below is keyed on a uuid column.
	const venueid = venue?.id ?? NO_VENUE_ID;

	const { data: submissionTypes } = await db.getVenueSubmissionTypes(venueid);

	// The venue's roles and who holds them, so a CSV naming an editor per row can be
	// resolved against the people this venue already trusts rather than against every
	// scholar on the platform.
	const { data: roles } = await db.getVenueRoles(venueid);

	// Admins and the venue's priority-0 editors may import -- the same test as
	// public.isPriorityZero, which bulk_import_submissions re-checks: `accepted`, not
	// `active`, since an editor who has paused volunteering is still the venue's editor.
	const isAdmin = scholar !== null && venue !== null && venue.admins.includes(scholar.id);
	const editorRoleIDs = (roles ?? []).filter((r) => r.priority === 0).map((r) => r.id);
	const { data: editorVolunteering } =
		scholar === null || isAdmin || editorRoleIDs.length === 0
			? { data: [] }
			: await db.getScholarAcceptedVolunteering(scholar.id, editorRoleIDs);
	const mayImport = isAdmin || (editorVolunteering ?? []).length > 0;

	// Everyone else gets a notice saying they can't, and this is enough of every
	// submission the venue has to recognize and link one, which at a large venue is the
	// heaviest thing the page loads. Reading it for somebody who will be handed a refusal
	// spends all of that on a page that shows none of it.
	const { data: existingSubmissions } = mayImport
		? await db.getVenueSubmissionIdentities(venueid)
		: { data: null };

	const { data: commitments } = await db.getVenueCommitments(venueid);

	return {
		venue,
		submissionTypes,
		existingSubmissions: existingSubmissions ?? [],
		roles: roles ?? [],
		commitments: commitments ?? [],
		mayImport
	};
};
