import type { PageLoad } from './$types';

export const load: PageLoad = async ({ parent, params }) => {
	const { supabase } = await parent();

	const scholarID = params.id;

	// Get the scholar's commitments
	const { data: volunteers } = await supabase
		.from('volunteers')
		.select('*, roles(name, venueid, approver)')
		.eq('scholarid', scholarID);

	const venueids = volunteers
		? volunteers.map((c) => c.roles?.venueid).filter((v) => v !== undefined)
		: [];

	const { data: venues } =
		venueids.length > 0 ? await supabase.from('venues').select().in('id', venueids) : { data: [] };

	// Get the currencies for which the scholar is a minter
	const { data: minting } = await supabase
		.from('currencies')
		.select('*')
		.contains('minters', [scholarID]);

	// Get the scholar's editing
	const { data: editing } = await supabase
		.from('venues')
		.select('id, title')
		.contains('editors', [scholarID]);

	// Get the scholar's current tokens.
	const { data: tokens, error: tokensError } = await supabase
		.from('tokens')
		.select('*')
		.eq('scholar', scholarID);
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
		.or(`from_scholar.eq.${scholarID},to_scholar.eq.${scholarID}`);
	if (transactionsError) console.log(transactionsError);

	// Get pending transactions on currencies for which the scholar is a minter
	const { data: pending, error: pendingTransactionsError } = await supabase
		.from('transactions')
		.select('*')
		.eq('status', 'proposed')
		.in('currency', minting ? minting.map((c) => c.id) : []);
	if (pendingTransactionsError) console.log(pendingTransactionsError);

	// Get the scholar's submissions
	const { data: submissions, error: submissionsError } = await supabase
		.from('submissions')
		.select('*')
		.contains('authors', [scholarID]);
	if (submissionsError) console.log(submissionsError);

	// Get the scholar's approved reviewing assignments
	const { data: reviews, error: reviewsError } = await supabase
		.from('assignments')
		.select('*, submissions(*)')
		.eq('scholar', scholarID)
		.eq('completed', false)
		.eq('approved', true);
	if (reviewsError) console.log(reviewsError);

	// Get the roles for which the scholar is the role approver.
	const { data: approver, error: approverError } = await supabase
		.from('roles')
		.select('*')
		.in('approver', reviews?.map((c) => c.role) || []);
	if (approverError) console.log(approverError);

	// Get the assignments for which the scholar is the role approver, to show in the scholar's dashboard.
	const { data: approvals, error: approvalsError } = await supabase
		.from('assignments')
		.select('*, scholars(*), submissions(*)')
		.in('role', approver?.map((r) => r.id) || [])
		.eq('approved', false);
	if (approvalsError) console.log(approvalsError);

	return {
		commitments: volunteers,
		venues,
		editing,
		tokens: tokens,
		transactions: transactions,
		submissions: submissions,
		currencies: currencies,
		minting: minting,
		pending: pending,
		reviews: reviews,
		approvals: approvals
	};
};
