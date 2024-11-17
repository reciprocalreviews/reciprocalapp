import type { LayoutLoad } from './$types';

export const load: LayoutLoad = async ({ parent, params }) => {
	const { supabase } = await parent();

	// Get the scholar record
	const { data: scholar } = await supabase.from('scholars').select().eq('id', params.id).single();

	return {
		scholar
	};
};
