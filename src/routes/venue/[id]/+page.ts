import type { PageLoad } from './$types.js';

export const load: PageLoad = async ({ parent, params }) => {
	const { supabase, user, venue } = await parent();

	const venueid = params.id;

	// Get the matching venu's currency.
	const { data: currency, error: currencyError } = venue
		? await supabase.from('currencies').select().eq('id', venue.currency).single()
		: { data: null };
	if (currencyError) console.error(currencyError);

	// Get the matching venue's roles.
	const { data: roles, error: rolesError } = await supabase
		.from('roles')
		.select()
		.eq('venueid', venueid);

	if (rolesError) console.error(rolesError);

	// Get all volunteers for the venue.
	const { data: volunteers, error: volunteersError } = user
		? await supabase.from('volunteers').select('*, roles (venueid)').eq('roles.venueid', venueid)
		: { data: null };
	if (volunteersError) console.error(volunteersError);

	// See how many tokens the venue posseses.
	const { data: tokens, error: tokensError } = await supabase
		.from('tokens')
		.select('*')
		.eq('venue', venueid);
	if (tokensError) console.error(tokensError);

	// See how many transactions the venue is part of.
	const { count: transactionCount, error: transactionsError } = await supabase
		.from('transactions')
		.select('*', { count: 'exact' })
		.or(`from_venue.eq.${venueid},to_venue.eq.${venueid}`);
	if (transactionsError) console.error(transactionsError);

	// See how many submissions are in the venue, for display.
	const { count: submissionCount, error: submissionsError } = await supabase
		.from('submissions')
		.select('*', { count: 'exact' })
		.eq('venue', venueid);
	if (submissionsError) console.error(submissionsError);

	return {
		venue,
		currency,
		roles,
		volunteers,
		tokens: tokens,
		transactionCount,
		submissionCount
	};
};
