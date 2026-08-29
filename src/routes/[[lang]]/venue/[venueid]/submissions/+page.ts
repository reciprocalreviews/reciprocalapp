import { NO_VENUE_ID } from '$lib/data/venuePath';
import type { PageLoad } from './$types.js';

export const load: PageLoad = async ({ parent, params }) => {
	const { db, venue, scholar } = await parent();

	const uid = scholar?.id ?? null;

	// The URL segment may be the venue's web address, so the id comes from the venue the
	// layout resolved, never from the param — every query below is keyed on a uuid column.
	const venueid = venue?.id ?? NO_VENUE_ID;

	// Get the venue's submissions.
	const { data: submissions } = await db.getVenueSubmissions(venueid);

	const admin = venue !== null && uid !== null && venue.admins.includes(uid);

	// Get all roles.
	const { data: roles } =
		// Missing data? Return nothing.
		uid === null ? { data: [] } : await db.getVenueRoles(venueid);

	const roleids = roles?.map((role) => role.id) ?? [];

	// Admin? Get all the volunteers. Non-admin? Get all commitments that are active, approved, and a role for this venue.
	const { data: volunteering } =
		uid === null
			? { data: [] }
			: admin
				? await db.getVolunteersByRoles(roleids)
				: await db.getScholarActiveVolunteering(uid, roleids);

	// Get all selectable assignments for the venue, according to the RLS policy.
	const { data: assignments } = uid === null ? { data: [] } : await db.getVenueAssignments(venueid);

	// Which submissions already have an editor. A boolean per submission rather than a
	// read of `assignments`: the venue's editors can see its submissions but none of its
	// assignments, so the list would otherwise call every submission unclaimed for exactly
	// the people the flag is for.
	const { data: submissionEditors } =
		uid === null ? { data: [] } : await db.getVenueSubmissionEditors(venueid);

	// Transactions in the submissions. Only retrieve IDs to preserve confidentiality.
	const { data: transactions } =
		submissions === null
			? { data: null }
			: await db.getSubmissionTransactionIDs(
					submissions.map((submission) => submission.transactions).flat()
				);

	// Find all conflicts for the current user.
	const { data: conflicts } = uid === null ? { data: [] } : await db.getScholarConflicts(uid);

	// Fetch names of scholars referenced as authors or assigned reviewers so
	// the submissions filter can match against them. Assignment rows are
	// already RLS-gated, so reviewer-name visibility follows the same rules
	// as the rest of the page; author-name visibility is enforced client-side
	// per role.anonymous_authors.
	const scholarIDs = [
		...new Set([
			...(submissions ?? []).flatMap((s) => s.authors),
			...(assignments ?? []).map((a) => a.scholar)
		])
	];
	const { data: scholars } =
		scholarIDs.length === 0 ? { data: [] } : await db.getScholarNames(scholarIDs);

	// Find all of the submissions types for the venue.
	const { data: submissionTypes } = await db.getVenueSubmissionTypes(venueid);

	// Get the venue's preference levels (may be empty).
	const { data: preferenceLevels } = await db.getVenuePreferenceLevels(venueid);

	return {
		venue,
		submissions,
		volunteering,
		roles,
		assignments,
		submissionEditors,
		transactions,
		conflicts,
		submissionTypes,
		preferenceLevels,
		scholars
	};
};
