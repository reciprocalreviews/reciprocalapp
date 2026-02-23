import type { PageLoad } from './$types.js';

export const load: PageLoad = async ({ parent, params }) => {
	const { supabase, venue } = await parent();

	const venueid = params.venueid;

	// Find all of the submissions types for the venue.
	const { data: submissionTypes, error: submissionTypesError } = await supabase
		.from('submission_types')
		.select('*')
		.eq('venue', venueid);
	if (submissionTypesError) console.error(submissionTypesError);

	return {
		venue,
		submissionTypes
	};
};
