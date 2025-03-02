import getVenueRoles from '$lib/data/getVenueRoles.js';
import type { PageLoad } from './$types.js';

export const load: PageLoad = async ({ parent, params }) => {
	const { supabase, user } = await parent();

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

	// Get the roles of the authenticated user so we can find the submissions for which they have a role.
	const { data: volunteerRoles, error: volunteerRolesError } =
		user === null
			? { data: null, error: null }
			: await supabase.from('volunteers').select('roleid').eq('scholarid', user.id);
	if (volunteerRolesError) console.error(volunteerRolesError);

	const volunteerRoleIDs = volunteerRoles === null ? [] : volunteerRoles.map((r) => r.roleid);

	// The the venues for which this user is editor
	const { data: venues, error: venuesError } =
		user === null
			? { data: null, error: null }
			: await supabase.from('venues').select('id').contains('editors', [user.id]);
	if (venuesError) console.log(venuesError);

	const editorVenueIDs = venues === null ? [] : venues.map((v) => v.id);

	// Get the assignments associated with the submission and either the role of the
	// authenticated user or in a venue for which this is the editor.
	const { data: assignments, error: assignmentsError } =
		submission === null
			? { data: null, error: null }
			: await supabase
					.from('assignments')
					.select('*')
					.eq('submission', submission.id)
					.or(`role.in.(${volunteerRoleIDs.join(',')}),venue.in.(${editorVenueIDs.join(',')})`);
	if (assignmentsError) console.error(assignmentsError);

	return {
		submission,
		venue,
		authors,
		previous: previous !== null && previous.length > 0 ? previous[0] : null,
		transactions,
		assignments,
		roles
	};
};
