import type { PageLoad } from './$types.js';

export const load: PageLoad = async ({ parent, params }) => {
	const { db } = await parent();

	// Get all currencies, so the page can show them in a dropdown.
	const { data: currencies } = await db.getCurrencies();

	return {
		currencies: currencies ?? null
	};
};
