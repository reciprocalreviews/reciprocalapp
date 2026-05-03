import type { PageLoad } from './$types.js';

export const load: PageLoad = async ({ parent, params }) => {
	const { supabase, venue } = await parent();

	const venueid = params.venueid;

	const { data: submissionTypes } = await supabase
		.from('submission_types')
		.select('*')
		.eq('venue', venueid);

	const { data: existingSubmissions } = await supabase
		.from('submissions')
		.select('externalid')
		.eq('venue', venueid);

	return {
		venue,
		submissionTypes,
		existingExternalIDs: (existingSubmissions ?? []).map((s) => s.externalid)
	};
};
