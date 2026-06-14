import type { LayoutLoad } from './$types';

export const load: LayoutLoad = async ({ parent, params }) => {
	const { db } = await parent();

	const { data: currency } = await db.getCurrency(params.id);

	return {
		currency: currency
	};
};
