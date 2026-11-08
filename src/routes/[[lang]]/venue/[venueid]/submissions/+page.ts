import { redirect } from '@sveltejs/kit';
import { NO_VENUE_ID } from '#lib/data/venuePath.js';
import type { PageLoad } from './$types.js';

export const load: PageLoad = async ({ parent, params, url }) => {
	const { db, venue, scholar } = await parent();

	const uid = scholar?.id ?? null;

	// The URL segment may be the venue's web address, so the id comes from the venue the
	// layout resolved, never from the param — every query below is keyed on a uuid column.
	const venueid = venue?.id ?? NO_VENUE_ID;

	// The decision-letter snippet links here by manuscript ID, which is all a reviewing
	// platform knows, so send the editor on to that submission's close-out. A manuscript
	// this viewer can't see, or that two submissions share, stays on the list, filtered to it.
	const close = url.searchParams.get('close');
	if (close !== null && close.length > 0 && venue !== null) {
		const { data: matches } = await db.getPreviousSubmissionByExternalID(venue.id, close);
		if (matches !== null && matches.length === 1)
			redirect(
				303,
				url.pathname.replace(/\/submissions\/?$/, `/submission/${matches[0].id}`) + '?close'
			);
	}

	// The list shows one state at a time: active submissions by default, done ones with
	// `?done`. Filtered here rather than on the page, so the active list a bidder reads,
	// and every read below keyed on it, doesn't grow with the venue's history.
	const done = url.searchParams.has('done');

	// Get the venue's submissions in that state.
	const { data: submissions } = await db.getVenueSubmissions(venueid, done);

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

	// The viewer's bid budget in each biddable role they volunteer for, keyed by role.
	const bidRoles = (roles ?? []).filter(
		(role) =>
			role.biddable &&
			(volunteering ?? []).some(
				(v) => v.roleid === role.id && v.scholarid === uid && v.active && v.accepted === 'accepted'
			)
	);
	const bidBudgets = Object.fromEntries(
		await Promise.all(
			bidRoles.map(async (role) => [role.id, (await db.getBidBudget(role.id)).data] as const)
		)
	);

	// Get all selectable assignments for the venue, according to the RLS policy.
	const { data: assignments } = uid === null ? { data: [] } : await db.getVenueAssignments(venueid);

	// Which submissions already have an editor. A boolean per submission rather than a
	// read of `assignments`: the venue's editors can see its submissions but none of its
	// assignments, so the list would otherwise call every submission unclaimed for exactly
	// the people the flag is for.
	const { data: submissionEditors } =
		uid === null ? { data: [] } : await db.getVenueSubmissionEditors(venueid);

	// Transactions in the submissions. Only the id and status, to preserve confidentiality:
	// the status is what says whether a charge was paid.
	const { data: transactions } =
		submissions === null
			? { data: null }
			: await db.getSubmissionTransactionStatuses(
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

	// How many assignments from imports this viewer could match, for the notice that links
	// to the page listing them. RLS counts only the rows the viewer could approve.
	const { data: unmatchedCount } =
		uid === null ? { data: 0 } : await db.countUnmatchedAssignments(venueid);

	return {
		venue,
		done,
		submissions,
		unmatchedCount,
		volunteering,
		bidBudgets,
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
