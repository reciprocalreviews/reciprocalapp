import type { PageLoad } from './$types.js';

export const load: PageLoad = async ({ parent, params }) => {
	const { supabase, user, venue } = await parent();

	const venueid = params.venueid;

	// Get the matching venue's currency.
	const { data: currency, error: currencyError } = venue
		? await supabase.from('currencies').select().eq('id', venue.currency).single()
		: { data: null };
	if (currencyError) console.error(currencyError);

	// Get the current's minter's emails.
	const { data: minters, error: mintersError } = currency
		? await supabase.from('scholars').select().in('id', currency.minters)
		: { data: null };
	if (mintersError) console.error(mintersError);

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

	return {
		venue,
		roles,
		volunteers,
		currency,
		minters
	};
};
