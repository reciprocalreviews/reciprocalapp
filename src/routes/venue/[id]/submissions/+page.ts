import type { PageLoad } from './$types.js';

export const load: PageLoad = async ({ parent, params }) => {
	const { supabase, venue } = await parent();

	const venueid = params.id;

	// Get the venue's submissions.
	const { data: submissions, error: submissionsError } = await supabase
		.from('submissions')
		.select('*')
		.eq('venue', venueid);
	if (submissionsError) console.error(submissionsError);

	return {
		venue,
		submissions
	};
};
