import type { PageLoad } from './$types.js';

export const load: PageLoad = async ({ parent, params }) => {
	const { supabase } = await parent();

	const { data: proposal, error: proposalError } = await supabase
		.from('proposals')
		.select()
		.eq('id', params.id)
		.single();
	const { data: supporters, error: supportersError } = await supabase
		.from('supporters')
		.select('id, scholarid(id, name, email), message, created')
		.eq('proposalid', params.id);

	return {
		proposal: proposal && proposalError === null ? proposal : null,
		supporters: supporters && supportersError === null ? supporters : null
	};
};
