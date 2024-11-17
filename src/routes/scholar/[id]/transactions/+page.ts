import type { PageLoad } from './$types';

export const load: PageLoad = async ({ parent, params }) => {
	const { supabase } = await parent();

	// Get the scholar record
	const { data: scholar } = await supabase.from('scholars').select().eq('id', params.id).single();

	// Get the scholar's most recent transactions.
	const { data: transactions, error: transactionsError } = await supabase
		.from('transactions')
		.select()
		.or(`from_scholar.eq.${params.id},to_scholar.eq.${params.id}`)
		.order('created', { ascending: false })
		.limit(5);
	if (transactionsError) console.log(transactionsError);

	return {
		scholar,
		transactions
	};
};
