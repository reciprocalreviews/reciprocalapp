import getTransactionCurrencies from '$lib/data/getTransactionCurrencies';
import getTransactionVenues from '$lib/data/getTransactionVenues';
import SupabaseCRUD from '$lib/data/SupabaseCRUD.svelte';
import { enUS } from '../../../../locale/Locale';
import type { PageLoad } from './$types';

export const load: PageLoad = async ({ parent, params }) => {
	const { supabase } = await parent();

	const CRUD = new SupabaseCRUD(supabase, enUS);

	// Get the scholar's most recent transactions.
	const {
		data: transactions,
		count,
		error: transactionsError
	} = await CRUD.getVenueTransactions(params.venueid);
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

	// Get the venue's tokens.
	const { data: tokens, error: tokensError } = await supabase
		.from('tokens')
		.select('*')
		.eq('venue', params.venueid);
	if (tokensError) console.error(tokensError);

	return {
		transactions,
		venues,
		currencies,
		tokens,
		count
	};
};
