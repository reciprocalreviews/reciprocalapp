import type { PageLoad } from './$types.js';

export const load: PageLoad = async ({ parent, params }) => {
	const { supabase } = await parent();

	const { data: venue } = await supabase.from('venues').select().eq('id', params.id).single();
	const { data: currency } = venue
		? await supabase.from('currencies').select().eq('id', venue.currency).single()
		: { data: null };
	const { data: roles } = venue
		? await supabase.from('roles').select().eq('venueid', venue.id)
		: { data: null };
	const { data: commitments } = venue
		? await supabase.from('commitments').select().eq('venueid', venue.id)
		: { data: null };

	return {
		venue,
		currency,
		roles,
		commitments
	};
};
