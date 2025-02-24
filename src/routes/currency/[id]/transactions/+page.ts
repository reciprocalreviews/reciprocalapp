import getTransactionVenues from '$lib/data/getTransactionVenues';
import type { PageLoad } from './$types';

export const load: PageLoad = async ({ parent, params }) => {
	const { supabase } = await parent();

	// Get the currency's most recent transactions.
	const { data: transactions, error: transactionsError } = await supabase
		.from('transactions')
		.select()
		.eq('currency', params.id);
	if (transactionsError) console.log(transactionsError);

	// Is the current scholar a minter on the venue?
	const { data: currency, error: currencyError } = await supabase
		.from('currencies')
		.select()
		.eq('id', params.id)
		.single();
	if (currencyError) console.log(currencyError);

	const { data: venues, error: venueError } =
		transactions === null
			? { data: null, error: null }
			: await getTransactionVenues(supabase, transactions);
	if (venueError) console.log(venueError);

	return {
		currency,
		transactions,
		venues
	};
};
