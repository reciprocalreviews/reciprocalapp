import type { PageLoad } from './$types.js';

export const load: PageLoad = async ({ parent, params }) => {
	const { supabase, user } = await parent();

	const venueid = params.id;

	// Get the matching venue.
	const { data: venue } = await supabase.from('venues').select().eq('id', venueid).single();
	// The commitments to the venue's roles.
	const { data: commitments, error } = user
		? await supabase
				.from('volunteers')
				.select('*, scholars (name), roles (name, venueid)')
				.eq('roles.venueid', venueid)
		: { data: null };
	if (error) console.error('Failed to load commitments:', error);

	return {
		venue,
		commitments
	};
};
