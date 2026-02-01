import type { PageLoad } from './$types.js';

export const load: PageLoad = async ({ parent, params }) => {
	const { supabase } = await parent();

	// Get all currencies, so the page can show them in a dropdown.
	const { data: currencies, error: currenciesError } = await supabase
		.from('currencies')
		.select('*');

	return {
		currencies: currencies && currenciesError === null ? currencies : null
	};
};
