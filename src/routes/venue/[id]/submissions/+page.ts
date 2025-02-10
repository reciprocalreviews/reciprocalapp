import type { PageLoad } from './$types.js';

export const load: PageLoad = async ({ parent, params }) => {
	const { supabase, venue, user } = await parent();

	const venueid = params.id;

	// Get the venue's submissions.
	const { data: submissions, error: submissionsError } = await supabase
		.from('submissions')
		.select('*')
		.eq('venue', venueid);
	if (submissionsError) console.error(submissionsError);

	const editor = venue !== null && user !== null && venue.editors.includes(user.id);

	// Get all roles.
	const { data: roles, error: rolesError } =
		// Missing data? Return nothing.
		user === null
			? { data: [], error: null }
			: await supabase.from('roles').select('*').eq('venueid', venueid);
	if (rolesError) console.error(rolesError);

	const roleids = roles?.map((role) => role.id) ?? [];

	// Editor? Get all the volunteers. Non-editor? Get all commitments that are active, approved, and a role for this venue.
	const { data: volunteering, error: volunteeringError } =
		user === null
			? { data: [], error: null }
			: editor
				? await supabase.from('volunteers').select('*').in('roleid', roleids)
				: await supabase
						.from('volunteers')
						.select('*')
						.eq('scholarid', user.id)
						.eq('active', true)
						.eq('accepted', 'accepted')
						.in('roleid', roleids);
	if (volunteeringError) console.error(volunteeringError);

	// Editor? Get all the assignments. Non-editor? Get the assignments the scholar has for this venue
	const { data: assignments, error: assignmentsError } =
		user === null
			? { data: [], error: null }
			: editor
				? await supabase.from('assignments').select('*').eq('venue', venueid)
				: await supabase
						.from('assignments')
						.select('*')
						.eq('scholar', user.id)
						.eq('venue', venueid);
	if (assignmentsError) console.error(assignmentsError);

	return { venue, submissions, volunteering, roles, assignments };
};
