import type { PageLoad } from './$types.js';

export const load: PageLoad = async ({ parent, params }) => {
	const { supabase, user } = await parent();

	const venueid = params.id;

	// Get the matching venue.
	const { data: venue, error: venueError } = await supabase
		.from('venues')
		.select()
		.eq('id', venueid)
		.single();
	if (venueError) console.log(venueError);

	// Get the matching venu's currency.
	const { data: currency, error: currencyError } = venue
		? await supabase.from('currencies').select().eq('id', venue.currency).single()
		: { data: null };
	if (currencyError) console.log(currencyError);

	// Get the matching venue's roles.
	const { data: roles, error: rolesError } = await supabase
		.from('roles')
		.select()
		.eq('venueid', venueid);
	if (rolesError) console.log(rolesError);

	// Get any commitments the user has made to the venue.
	const { data: commitments, error: commitmentsError } = user
		? await supabase
				.from('volunteers')
				.select('*, roles (venueid)')
				.eq('roles.venueid', venueid)
				.eq('scholarid', user.id)
		: { data: null };
	if (commitmentsError) console.log(commitmentsError);

	// See how many tokens the venue posseses.
	const { data: tokens, error: tokensError } = await supabase
		.from('tokens')
		.select()
		.eq('venue', venueid);
	if (tokensError) console.log(tokensError);

	return {
		venue,
		currency,
		roles,
		commitments,
		tokens: tokens?.length ?? null
	};
};
