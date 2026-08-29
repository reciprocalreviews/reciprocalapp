import { NO_VENUE_ID } from '$lib/data/venuePath';
import type { PageLoad } from './$types';

export const load: PageLoad = async ({ parent }) => {
	const { db, venue } = await parent();

	// The URL segment may be the venue's web address, so the id comes from the venue the
	// layout resolved, never from the param — the queries below are keyed on uuid columns.
	const venueid = venue?.id ?? NO_VENUE_ID;

	// Get the venue's most recent transactions.
	const { data: transactions, count } = await db.getVenueTransactions(venueid);

	const { data: venues } =
		transactions === null ? { data: null } : await db.getTransactionVenues(transactions);

	const { data: currencies } =
		transactions === null ? { data: null } : await db.getTransactionCurrencies(transactions);

	// Get the venue's tokens.
	const { data: tokens } = await db.getVenueTokens(venueid);

	return {
		transactions,
		venues,
		currencies,
		tokens,
		count
	};
};
