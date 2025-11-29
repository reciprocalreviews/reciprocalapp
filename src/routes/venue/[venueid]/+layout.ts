import type { LayoutLoad } from './$types.js';

export const load: LayoutLoad = async ({ parent, params }) => {
	const { supabase } = await parent();

	const venueid = params.venueid;

	// Get the matching venue.
	const { data: venue, error: venueError } = await supabase
		.from('venues')
		.select()
		.eq('id', venueid)
		.single();
	if (venueError) console.log(venueError);

	return {
		venue
	};
};
