import getVenueRoles from '$lib/data/getVenueRoles.js';
import type { PageLoad } from './$types.js';

export const load: PageLoad = async ({ parent, params }) => {
	const { supabase, venue, scholar } = await parent();

	const uid = scholar?.id ?? null;

	const venueid = params.venueid;

	// Get the venue's submissions.
	const { data: submissions, error: submissionsError } = await supabase
		.from('submissions')
		.select('*')
		.eq('venue', venueid);
	if (submissionsError) console.error(submissionsError);

	const admin = venue !== null && uid !== null && venue.admins.includes(uid);

	// Get all roles.
	const { data: roles, error: rolesError } =
		// Missing data? Return nothing.
		uid === null ? { data: [], error: null } : await getVenueRoles(supabase, venueid);
	if (rolesError) console.error(rolesError);

	const roleids = roles?.map((role) => role.id) ?? [];

	// Admin? Get all the volunteers. Non-admin? Get all commitments that are active, approved, and a role for this venue.
	const { data: volunteering, error: volunteeringError } =
		uid === null
			? { data: [], error: null }
			: admin
				? await supabase.from('volunteers').select('*').in('roleid', roleids)
				: await supabase
						.from('volunteers')
						.select('*')
						.eq('scholarid', uid)
						.eq('active', true)
						.eq('accepted', 'accepted')
						.in('roleid', roleids);
	if (volunteeringError) console.error(volunteeringError);

	// Get all selectable assignments for the venue, according to the RLS policy.
	const { data: assignments, error: assignmentsError } =
		uid === null
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
		uid === null
			? { data: [], error: null }
			: await supabase.from('conflicts').select('*').eq('scholarid', uid);
	if (conflictsError) console.error(conflictsError);

	// Find all of the submissions types for the venue.
	const { data: submissionTypes, error: submissionTypesError } = await supabase
		.from('submission_types')
		.select('*')
		.eq('venue', venueid);
	if (submissionTypesError) console.error(submissionTypesError);

	return {
		venue,
		submissions,
		volunteering,
		roles,
		assignments,
		transactions,
		conflicts,
		submissionTypes
	};
};
