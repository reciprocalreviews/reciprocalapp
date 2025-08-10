import type { PageLoad } from './$types';

export const load: PageLoad = async ({ parent, params }) => {
	const { supabase } = await parent();

	// Get current stewards.
	const { data: stewards } = await supabase.from('scholars').select('id, name').eq('steward', true);

	return {
		stewards
	};
};
