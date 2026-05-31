import type { PageLoad } from './$types.js';

export const load: PageLoad = async ({ parent, params }) => {
	const { supabase, venue, scholar } = await parent();

	const venueid = params.venueid;

	// Find all of the submissions types for the venue.
	const { data: submissionTypes, error: submissionTypesError } = await supabase
		.from('submission_types')
		.select('*')
		.eq('venue', venueid);
	if (submissionTypesError) console.error(submissionTypesError);

	// Find the submissions in this venue the authenticated scholar authored, so
	// they can link a new submission to an on-platform predecessor (#124).
	const { data: priorSubmissions, error: priorSubmissionsError } = scholar?.id
		? await supabase
				.from('submissions')
				.select('id, externalid, title, submission_type')
				.eq('venue', venueid)
				.contains('authors', [scholar.id])
		: { data: [], error: null };
	if (priorSubmissionsError) console.error(priorSubmissionsError);

	return {
		venue,
		submissionTypes,
		priorSubmissions: priorSubmissions ?? []
	};
};
