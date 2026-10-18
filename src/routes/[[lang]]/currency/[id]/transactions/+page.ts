import type { PageLoad } from './$types';

export const load: PageLoad = async ({ parent, params }) => {
	const { db } = await parent();

	// Get the currency's most recent transactions.
	const { data: transactions, count } = await db.getCurrencyTransactions(params.id);

	// Is the current scholar a minter on the venue?
	const { data: currency } = await db.getCurrency(params.id);

	const { data: venues } =
		transactions === null ? { data: null } : await db.getTransactionVenues(transactions);

	return {
		currency,
		transactions,
		venues,
		count
	};
};
