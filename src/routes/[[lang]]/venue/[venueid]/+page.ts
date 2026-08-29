import type { PageLoad } from './$types.js';

export const load: PageLoad = async ({ parent, params }) => {
	const { db, venue } = await parent();

	const venueid = params.venueid;

	// Get the matching venue's currency.
	const { data: currency } = venue ? await db.getCurrency(venue.currency) : { data: null };

	// Get the matching venue's roles.
	const { data: roles } = await db.getVenueRoles(venueid);

	// Get all volunteers for the venue.
	const { data: volunteers } = await db.getVenueVolunteers(venueid);

	// See how many tokens the venue posseses.
	const { data: tokens } = await db.getVenueTokens(venueid);

	// See how many transactions the venue is part of.
	const { data: transactionCount } = await db.getVenueTransactionCount(venueid);

	// See how many submissions are in the venue, for display.
	const { data: submissionCount } = await db.getVenueSubmissionCount(venueid);

	// Get all the submission types
	const { data: types } = await db.getVenueSubmissionTypes(venueid);

	// Get all the compensation
	const { data: compensation } = await db.getCompensationByTypes(types?.map((s) => s.id) ?? []);

	// Get all the venues one can gift to.
	const { data: venues } = await db.getVenues();

	// Get the venue's preference levels (may be empty if not configured).
	const { data: preferenceLevels } = await db.getVenuePreferenceLevels(venueid);

	return {
		venue,
		currency,
		roles,
		volunteers,
		tokens: tokens,
		transactionCount,
		submissionCount,
		venues,
		types,
		compensation,
		preferenceLevels
	};
};
