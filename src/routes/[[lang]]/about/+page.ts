import type { PageLoad } from './$types';

export const load: PageLoad = async ({ parent, params }) => {
	const { db } = await parent();

	// Get current stewards.
	const { data: stewards } = await db.getStewards();

	return {
		stewards
	};
};
