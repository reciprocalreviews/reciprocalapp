import getVenueRoles from '$lib/data/getVenueRoles.js';
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

	// Get the previous submission
	const { data: previous, error: previousError } =
		submission !== null && submission.previousid !== null && submission.previousid.length > 0
			? await supabase.from('submissions').select('*').eq('externalid', submission.previousid)
			: { data: null, error: null };
	if (previousError) console.error(previousError);

	// Get the transactions for the submission
	const { data: transactions, error: transactionsError } =
		submission === null
			? { data: null, error: null }
			: await supabase.from('transactions').select('*').in('id', submission.transactions);
	if (transactionsError) console.error(transactionsError);

	// Get all of the roles for this venue.
	const { data: roles, error: rolesError } =
		venue === null ? { data: null, error: null } : await getVenueRoles(supabase, venue.id);
	if (rolesError) console.error(rolesError);

	// Get the assignments associated with the submission and either the role of the
	// authenticated user or in a venue for which this is the editor.
	const { data: assignments, error: assignmentsError } =
		submission === null
			? { data: null, error: null }
			: await supabase.from('assignments').select('*').eq('submission', submission.id);
	if (assignmentsError) console.error(assignmentsError);

	// Get the volunteer records of those assigned so we can render their expertise.
	const { data: volunteers, error: volunteersError } =
		assignments === null
			? { data: null, error: null }
			: await supabase
					.from('volunteers')
					.select('*')
					.in(
						'roleid',
						assignments.map((a) => a.role)
					);
	if (volunteersError) console.error(volunteersError);

	return {
		submission,
		venue,
		authors,
		previous: previous !== null && previous.length > 0 ? previous[0] : null,
		transactions,
		assignments,
		volunteers,
		roles
	};
};
