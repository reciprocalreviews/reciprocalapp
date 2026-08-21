import type { PageLoad } from './$types';

export const load: PageLoad = async ({ parent }) => {
	const { db } = await parent();

	const { data: proposals } = await db.getUnassignedProposals();
	const { data: allVenues } = await db.getVenues();

	return {
		proposals,
		venues: allVenues?.filter((v) => v.inactive === null) ?? null,
		inactiveVenues: allVenues?.filter((v) => v.inactive !== null) ?? null
	};
};
