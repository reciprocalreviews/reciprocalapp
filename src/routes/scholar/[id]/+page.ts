import type { PageLoad } from './$types';

export const load: PageLoad = async ({ parent, params }) => {
	const { supabase } = await parent();

	// Get the scholar record
	const { data: scholar } = await supabase.from('scholars').select().eq('id', params.id).single();

	// Get the scholar's commitments
	const { data: commitments } = await supabase
		.from('volunteers')
		.select('*, roles(name, venueid)')
		.eq('scholarid', params.id);

	const venueids = commitments
		? commitments.map((c) => c.roles?.venueid).filter((v) => v !== undefined)
		: [];

	const { data: venues } =
		venueids.length > 0 ? await supabase.from('venues').select().in('id', venueids) : { data: [] };

	// Get the currencies for which the scholar is a minter
	const { data: minting } = await supabase
		.from('currencies')
		.select('*')
		.contains('minters', [params.id]);

	// Get the scholar's editing
	const { data: editing } = await supabase
		.from('venues')
		.select('id, title')
		.contains('editors', [params.id]);

	// Get the scholar's current tokens.
	const { data: tokens, error: tokensError } = await supabase
		.from('tokens')
		.select('*')
		.eq('scholar', params.id);
	if (tokensError) console.log(tokensError);

	// Get the currencies that the tokens use
	const currencyIDs = tokens ? tokens.map((t) => t.currency) : [];
	const { data: currencies, error: currenciesError } = await supabase
		.from('currencies')
		.select('*')
		.in('id', currencyIDs);
	if (currenciesError) console.log(currenciesError);

	// Get the scholar's most recent transactions.
	const { count: transactions, error: transactionsError } = await supabase
		.from('transactions')
		.select('*', { count: 'exact' })
		.or(`from_scholar.eq.${params.id},to_scholar.eq.${params.id}`);
	if (transactionsError) console.log(transactionsError);

	// Get the scholar's submissions
	const { data: submissions, error: submissionsError } = await supabase
		.from('submissions')
		.select('*')
		.contains('authors', [params.id]);
	if (submissionsError) console.log(submissionsError);

	return {
		scholar,
		commitments,
		venues,
		editing,
		tokens: tokens,
		transactions: transactions,
		submissions: submissions,
		currencies: currencies,
		minting: minting
	};
};
