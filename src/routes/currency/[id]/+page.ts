import type { PageLoad } from './$types';

export const load: PageLoad = async ({ parent, params }) => {
	const { supabase } = await parent();

	const { data: venues, error: venuesError } = await supabase
		.from('venues')
		.select()
		.eq('currency', params.id);
	if (venuesError) console.log(venuesError.message);

	const { data: tokens, error: tokensError } = await supabase
		.from('tokens')
		.select()
		.eq('currency', params.id);
	if (tokensError) console.log(tokensError.message);

	const scholarCount = tokens
		? new Set(tokens.filter((token) => token.scholar !== null).map((token) => token.scholar)).size
		: null;

	const venueCount = tokens
		? new Set(tokens.filter((token) => token.venue !== null).map((token) => token.venue)).size
		: null;

	return {
		venues: venues,
		count: tokens?.length ?? null,
		scholarCount,
		venueCount
	};
};
