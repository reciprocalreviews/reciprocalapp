import type { PageLoad } from './$types.js';

export const load: PageLoad = async ({ parent }) => {
	const { scholar, venue } = await parent();

	// Only a venue admin can read the charges made to the venue (transactions RLS), so
	// anyone else would be told every submission was outstanding. Nothing is read here:
	// the IDs to check arrive with the form.
	const isAdmin = scholar !== null && venue !== null && venue.admins.includes(scholar.id);

	return { venue, isAdmin };
};
