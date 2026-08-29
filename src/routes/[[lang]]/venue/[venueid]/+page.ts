import { NO_VENUE_ID } from '$lib/data/venuePath';
import type { PageLoad } from './$types.js';

export const load: PageLoad = async ({ parent, params }) => {
	const { db, venue } = await parent();

	// The URL segment may be the venue's web address, so the id comes from the venue the
	// layout resolved, never from the param — every query below is keyed on a uuid column.
	const venueid = venue?.id ?? NO_VENUE_ID;

	// Get the matching venue's currency.
	const { data: currency } = venue ? await db.getCurrency(venue.currency) : { data: null };

	// Get the matching venue's roles.
	const { data: roles } = await db.getVenueRoles(venueid);

	// Get all volunteers for the venue.
	const { data: volunteers } = await db.getVenueVolunteers(venueid);

	// See how many tokens the venue possesses. A count, not the rows: the page
	// only ever showed the number, and a reserve serving a real community is far
	// past the `max_rows` cap that silently truncated the array this used to
	// count — a quarter-million-token reserve displayed as 1000.
	const { data: tokens } = venue
		? await db.getVenueTokenCount(venueid, venue.currency)
		: { data: null };

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
