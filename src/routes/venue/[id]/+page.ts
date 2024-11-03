import type { PageLoad } from './$types.js';

export const load: PageLoad = async ({ parent, params }) => {
	const { supabase, user } = await parent();

	const venueid = params.id;

	// Get the matching venue.
	const { data: venue } = await supabase.from('venues').select().eq('id', venueid).single();
	// Get the matching venu's currency.
	const { data: currency } = venue
		? await supabase.from('currencies').select().eq('id', venue.currency).single()
		: { data: null };
	// Get the matching venue's roles.
	const { data: roles } = await supabase.from('roles').select().eq('venueid', venueid);
	// Get any commitments the user has made to the venue.
	const { data: commitments, error } = user
		? await supabase
				.from('volunteers')
				.select('*, roles (venueid)')
				.eq('roles.venueid', venueid)
				.eq('scholarid', user.id)
		: { data: null };

	return {
		venue,
		currency,
		roles,
		commitments
	};
};
