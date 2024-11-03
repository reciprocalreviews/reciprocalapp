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

	// Get the scholar's editing
	const { data: editing } = await supabase
		.from('venues')
		.select('id, title')
		.contains('editors', [params.id]);

	return {
		scholar,
		commitments,
		venues,
		editing
	};
};
