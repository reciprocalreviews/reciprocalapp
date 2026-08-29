import type { PageLoad } from './$types';

export const load: PageLoad = async ({ parent, params }) => {
	const { db } = await parent();

	const { data: currency } = await db.getCurrency(params.id);

	const { data: venues } = await db.getCurrencyVenues(params.id);

	// Total supply and holder counts, aggregated in the database. This used to
	// fetch every token row in the currency and derive all three here — `.length`
	// for the supply and two `Set`s for the holders — which PostgREST silently
	// truncated at `max_rows`. A currency serving a real community reported a
	// supply of exactly 1000, with holder counts drawn from an arbitrary thousand
	// of its tokens.
	const { data: counts } = await db.getCurrencyHolderCounts(params.id);

	return {
		currency,
		venues: venues,
		count: counts?.supply ?? null,
		scholarCount: counts?.scholars ?? null,
		venueCount: counts?.venues ?? null
	};
};
