import type { PageLoad } from './$types';

export const load: PageLoad = async ({ parent }) => {
	const { db } = await parent();

	const { data: proposals } = await db.getUnassignedProposals();
	const { data: venues } = await db.getVenues();

	return {
		proposals,
		venues
	};
};
