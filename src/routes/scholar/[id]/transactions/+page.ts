import getTransactionCurrencies from '$lib/data/getTransactionCurrencies';
import getTransactionVenues from '$lib/data/getTransactionVenues';
import type { PageLoad } from './$types';

export const load: PageLoad = async ({ parent, params }) => {
	const { supabase } = await parent();

	// Get the scholar's most recent transactions.
	const { data: transactions, error: transactionsError } = await supabase
		.from('transactions')
		.select()
		.or(`from_scholar.eq.${params.id},to_scholar.eq.${params.id}`)
		.order('created_at', { ascending: false });
	if (transactionsError) console.log(transactionsError);

	const { data: venues, error: venueError } =
		transactions === null
			? { data: null, error: null }
			: await getTransactionVenues(supabase, transactions);
	if (venueError) console.log(venueError);

	const { data: currencies, error: currencyError } =
		transactions === null
			? { data: null, error: null }
			: await getTransactionCurrencies(supabase, transactions);
	if (currencyError) console.log(currencyError);

	return {
		transactions,
		venues,
		currencies
	};
};
