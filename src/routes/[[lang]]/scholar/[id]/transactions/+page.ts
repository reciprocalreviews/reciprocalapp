import type { PageLoad } from './$types';

export const load: PageLoad = async ({ parent, params }) => {
	const { db } = await parent();

	// Get the scholar's most recent transactions.
	const { data: transactions, count } = await db.getScholarTransactions(params.id);

	const { data: venues } =
		transactions === null ? { data: null } : await db.getTransactionVenues(transactions);

	const { data: currencies } =
		transactions === null ? { data: null } : await db.getTransactionCurrencies(transactions);

	return {
		transactions,
		venues,
		currencies,
		count
	};
};
