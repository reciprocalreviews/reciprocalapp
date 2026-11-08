import type { PageLoad } from './$types';

export const load: PageLoad = async ({ parent }) => {
	const { db } = await parent();

	// The steward list is what makes this page a set of people rather than a support
	// queue, so it is loaded here rather than left to render client-side.
	const { data: stewards } = await db.getStewards();

	return {
		stewards
	};
};
