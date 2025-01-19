import type { PageLoad } from './$types.js';

export const load: PageLoad = async ({ parent, params }) => {
	const { supabase } = await parent();

	const submissionid = params.id;

	// Get the submission.
	const { data: submission, error: submissionsError } = await supabase
		.from('submissions')
		.select('*')
		.eq('id', submissionid)
		.single();
	if (submissionsError) console.error(submissionsError);

	// Get the corresponding venue.
	const { data: venue, error: venueError } =
		submission === null
			? { data: null, error: null }
			: await supabase.from('venues').select('*').eq('id', submission.venue).single();
	if (venueError) console.error(venueError);

	// Get the authors
	const { data: authors, error: authorsError } =
		submission === null
			? { data: null, error: null }
			: await supabase.from('scholars').select('*').in('id', submission.authors);
	if (authorsError) console.error(authorsError);

	return {
		submission,
		venue,
		authors
	};
};
