import type { PageLoad } from './$types';

export const load: PageLoad = async ({ parent, params }) => {
	const { supabase } = await parent();

	// Get the scholar's most recent transactions.
	const { data: transactions, error: transactionsError } = await supabase
		.from('transactions')
		.select()
		.or(`from_venue.eq.${params.id},to_venue.eq.${params.id}`);
	if (transactionsError) console.log(transactionsError);

	return {
		transactions
	};
};
