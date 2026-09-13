import { submissionsCrumbs } from '$lib/data/breadcrumbs';
import { NO_VENUE_ID } from '$lib/data/venuePath';
import type { PageLoad } from './$types.js';

export const load: PageLoad = async ({ parent, params }) => {
	const { db, locale, scholar, venue } = await parent();

	// The URL segment may be the venue's web address, so the id comes from the venue the
	// layout resolved, never from the param — every query below is keyed on a uuid column.
	const venueid = venue?.id ?? NO_VENUE_ID;

	const { data: submissionTypes } = await db.getVenueSubmissionTypes(venueid);

	// Only an admin is ever shown the importer -- everyone else gets a notice saying so --
	// and this is enough of every submission the venue has to recognize and link one, which
	// at a large venue is the heaviest thing the page loads. Reading it for somebody who
	// will be handed a refusal spends all of that on a page that shows none of it.
	const isAdmin = scholar !== null && venue !== null && venue.admins.includes(scholar.id);

	const { data: existingSubmissions } = isAdmin
		? await db.getVenueSubmissionIdentities(venueid)
		: { data: null };

	// The venue's roles and who holds them, so a CSV naming an editor per row can be
	// resolved against the people this venue already trusts rather than against every
	// scholar on the platform.
	const { data: roles } = await db.getVenueRoles(venueid);

	const { data: commitments } = await db.getVenueCommitments(venueid);

	return {
		breadcrumbs: submissionsCrumbs(venue, locale),
		venue,
		submissionTypes,
		existingSubmissions: existingSubmissions ?? [],
		roles: roles ?? [],
		commitments: commitments ?? []
	};
};
