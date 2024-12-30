import type { LayoutLoad } from './$types.js';

export const load: LayoutLoad = async ({ parent, params }) => {
	const { supabase, user } = await parent();

	const venueid = params.id;

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
