import type { LayoutLoad } from './$types';

export const load: LayoutLoad = async ({ parent, params }) => {
	const { db } = await parent();

	// Get the scholar record
	const { data: scholar } = await db.getScholarRow(params.id);

	return {
		scholar
	};
};
