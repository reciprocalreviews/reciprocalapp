import type { PageLoad } from './$types.js';

export const load: PageLoad = async ({ parent, params }) => {
	const { supabase } = await parent();

	const { data } = await supabase.from('venues').select().eq('id', params.id).single();

	return {
		venue: data
	};
};
