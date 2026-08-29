import type { PageLoad } from './$types';

export const load: PageLoad = async ({ parent, params }) => {
	const { db } = await parent();

	const { data: currency } = await db.getCurrency(params.id);

	const { data: venues } = await db.getCurrencyVenues(params.id);

	const { data: tokens } = await db.getCurrencyTokens(params.id);

	const scholarCount = tokens
		? new Set(tokens.filter((token) => token.scholar !== null).map((token) => token.scholar)).size
		: null;

	const venueCount = tokens
		? new Set(tokens.filter((token) => token.venue !== null).map((token) => token.venue)).size
		: null;

	return {
		currency,
		venues: venues,
		count: tokens?.length ?? null,
		scholarCount,
		venueCount
	};
};
