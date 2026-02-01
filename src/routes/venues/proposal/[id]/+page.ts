import type { PageLoad } from './$types.js';

export const load: PageLoad = async ({ parent, params }) => {
	const { supabase } = await parent();

	const { data: proposal, error: proposalError } = await supabase
		.from('proposals')
		.select()
		.eq('id', params.id)
		.single();
	if (proposalError) console.error(proposalError);

	const { data: supporters, error: supportersError } = await supabase
		.from('supporters')
		.select('id, scholarid(id, name, email), message, created_at')
		.eq('proposalid', params.id);

	if (supportersError) console.error(supportersError);

	return {
		proposal: proposal ? proposal : null,
		supporters: supporters ? supporters : null
	};
};
