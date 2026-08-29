import type { PageLoad } from './$types.js';

export const load: PageLoad = async ({ parent, params }) => {
	const { db, scholar, venue } = await parent();

	const venueid = params.venueid;

	// Get the matching venue's currency.
	const { data: currency } = venue ? await db.getCurrency(venue.currency) : { data: null };

	// Get the matching venue's roles.
	const { data: roles } = await db.getVenueRoles(venueid);

	// Get all volunteers for the venue.
	const { data: volunteers } = scholar
		? await db.getVenueSettingsVolunteers(venueid)
		: { data: null };

	// Get all the submission types
	const { data: types } = await db.getVenueSubmissionTypes(venueid);

	// Get all the compensation
	const { data: compensation } = await db.getCompensationByTypes(types?.map((s) => s.id) ?? []);

	// Get the venue's preference levels (may be empty if not configured).
	const { data: preferenceLevels } = await db.getVenuePreferenceLevels(venueid);

	return {
		venue,
		roles,
		volunteers,
		currency,
		types,
		compensation,
		preferenceLevels
	};
};
