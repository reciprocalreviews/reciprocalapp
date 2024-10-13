import type { PageLoad } from './$types';

export const load: PageLoad = async ({ parent }) => {
	const { supabase } = await parent();

	const { data: proposals } = await supabase.from('proposals').select().is('venue', null);
	const { data: venues } = await supabase.from('venues').select();

	return {
		proposals,
		venues
	};
};
