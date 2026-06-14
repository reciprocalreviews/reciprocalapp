import type { PageLoad } from './$types';

export const load: PageLoad = async ({ parent, params }) => {
	const { db } = await parent();

	// Get the venue's most recent transactions.
	const { data: transactions, count } = await db.getVenueTransactions(params.venueid);

	const { data: venues } =
		transactions === null ? { data: null } : await db.getTransactionVenues(transactions);

	const { data: currencies } =
		transactions === null ? { data: null } : await db.getTransactionCurrencies(transactions);

	// Get the venue's tokens.
	const { data: tokens } = await db.getVenueTokens(params.venueid);

	return {
		transactions,
		venues,
		currencies,
		tokens,
		count
	};
};
