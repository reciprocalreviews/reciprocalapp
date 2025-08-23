import type { PageLoad } from './$types.js';

export const load: PageLoad = async ({ parent, params }) => {
	const { supabase } = await parent();

	const venueid = params.id;

	// Get the matching venue.
	const { data: venue } = await supabase.from('venues').select().eq('id', venueid).single();
	// The commitments to the venue's roles.
	const { data: commitments, error: commitmentsError } = await supabase
		.from('volunteers')
		.select('*, scholars (name, email, orcid), roles (name, venueid)')
		.eq('roles.venueid', venueid);
	if (commitmentsError) console.error('Failed to load commitments:', commitmentsError);

	const { data: roles, error: rolesError } = await supabase
		.from('roles')
		.select()
		.eq('venueid', venueid);
	if (rolesError) console.error('Failed to load roles:', rolesError);

	return {
		venue,
		commitments,
		roles
	};
};
