import getVenueRoles from '$lib/data/getVenueRoles.js';
import type { PageLoad } from './$types.js';

export const load: PageLoad = async ({ parent, params }) => {
	const { supabase, venue, user } = await parent();

	const venueid = params.venueid;

	// Get the venue's submissions.
	const { data: submissions, error: submissionsError } = await supabase
		.from('submissions')
		.select('*')
		.eq('venue', venueid);
	if (submissionsError) console.error(submissionsError);

	const admin = venue !== null && user !== null && venue.admins.includes(user.id);

	// Get all roles.
	const { data: roles, error: rolesError } =
		// Missing data? Return nothing.
		user === null ? { data: [], error: null } : await getVenueRoles(supabase, venueid);
	if (rolesError) console.error(rolesError);

	const roleids = roles?.map((role) => role.id) ?? [];

	// Admin? Get all the volunteers. Non-admin? Get all commitments that are active, approved, and a role for this venue.
	const { data: volunteering, error: volunteeringError } =
		user === null
			? { data: [], error: null }
			: admin
				? await supabase.from('volunteers').select('*').in('roleid', roleids)
				: await supabase
						.from('volunteers')
						.select('*')
						.eq('scholarid', user.id)
						.eq('active', true)
						.eq('accepted', 'accepted')
						.in('roleid', roleids);
	if (volunteeringError) console.error(volunteeringError);

	// Get all selectable assignments for the venue, according to the RLS policy.
	const { data: assignments, error: assignmentsError } =
		user === null
			? { data: [], error: null }
			: await supabase.from('assignments').select('*').eq('venue', venueid);
	if (assignmentsError) console.error(assignmentsError);

	// Transactions in the submissions. Only retrieve IDs to preserve confidentiality.
	const { data: transactions, error: transactionsError } =
		submissions === null
			? { data: null, error: null }
			: await supabase
					.from('transactions')
					.select('id')
					.in('id', submissions.map((submission) => submission.transactions).flat());
	if (transactionsError) console.error(transactionsError);

	// Find all conflicts for the current user.
	const { data: conflicts, error: conflictsError } =
		user === null
			? { data: [], error: null }
			: await supabase.from('conflicts').select('*').eq('scholarid', user.id);
	if (conflictsError) console.error(conflictsError);

	return { venue, submissions, volunteering, roles, assignments, transactions, conflicts };
};
