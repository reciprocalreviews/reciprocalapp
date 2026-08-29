import { NO_VENUE_ID } from '$lib/data/venuePath';
import type { PageLoad } from './$types';

export const load: PageLoad = async ({ parent, params }) => {
	// The venue comes from the layout, which is what resolves a web address to a venue; the
	// URL segment is not an id and must not be used as one.
	const { db, scholar, venue: resolved } = await parent();

	const venueid = resolved?.id ?? NO_VENUE_ID;
	const submissionid = params.submissionid;

	// Get the submission.
	const { data: submission } = await db.getSubmission(submissionid);

	// The venue, but only alongside a submission — a submission that isn't there means
	// there is nothing on this page to show it in.
	const venue = submission === null ? null : resolved;

	// Get the authors
	const { data: authors } =
		submission === null ? { data: null } : await db.getScholarsByIDs(submission.authors);

	// Get the previous submission. Prefer the explicit on-platform link
	// (submission.previous FK); fall back to the legacy/bulk free-text match of
	// previousid against an externalid in the same venue (#124).
	const { data: previous } =
		submission !== null && submission.previous !== null
			? await db.getPreviousSubmissionByID(submission.previous)
			: submission !== null && submission.previousid !== null && submission.previousid.length > 0
				? await db.getPreviousSubmissionByExternalID(venueid, submission.previousid)
				: { data: null };

	// Get the transactions for the submission
	const { data: transactions } =
		submission === null ? { data: null } : await db.getTransactionsByIDs(submission.transactions);

	// Get all of the roles for this venue.
	const { data: roles } = venue === null ? { data: null } : await db.getVenueRoles(venue.id);

	// Get the assignments associated with the submission and either the role of the
	// authenticated user or in a venue for which this is the editor.
	const { data: assignments } =
		submission === null ? { data: null } : await db.getSubmissionAssignments(submission.id);

	// Whether anyone holds the venue's editor role on this submission. A boolean rather
	// than a read of `assignments`, which is RLS-filtered: a venue editor who is not a
	// venue admin sees none of them, and would be told every submission is unclaimed.
	const { data: submissionEditors } = await db.getVenueSubmissionEditors(venueid);
	const submissionHasEditor =
		submissionEditors === null || submission === null
			? undefined
			: (submissionEditors.find((s) => s.submission === submission.id)?.has_editor ?? undefined);

	// Get the volunteer records of those assigned so we can render their expertise.
	const { data: volunteers } =
		assignments === null
			? { data: null }
			: await db.getVolunteersByRoles(assignments.map((a) => a.role));

	// The viewer's OWN accepted volunteer records among this venue's roles. Needed
	// by canViewSubmission's bidder branch: an accepted volunteer on any biddable
	// role may read every submission in the venue, whether or not they are assigned
	// to this one. `volunteers` above cannot answer this — it covers only the roles
	// that have assignments here.
	const { data: viewerVolunteering } =
		scholar === null || roles === null || roles.length === 0
			? { data: null }
			: await db.getScholarAcceptedVolunteering(
					scholar.id,
					roles.map((r) => r.id)
				);

	// Get the token balances of each volunteer in the venue's currency, so we can sort by them.
	const { data: balances } =
		volunteers === null || venue === null
			? { data: null }
			: await db.getTokenBalances(
					venue.currency,
					volunteers.map((v) => v.scholarid)
				);

	// Get the submission types in case we need to change it.
	const { data: submissionTypes } = await db.getVenueSubmissionTypes(venueid);

	// Names of scholars referenced by assignments, for stable sorting by family name.
	const assignmentScholarIDs = Array.from(new Set(assignments?.map((a) => a.scholar) ?? []));
	const { data: assignmentScholars } =
		assignmentScholarIDs.length === 0
			? { data: [] }
			: await db.getScholarNames(assignmentScholarIDs);

	// Get the venue's preference levels (may be empty) for rendering bid labels.
	const { data: preferenceLevels } = await db.getVenuePreferenceLevels(venueid);

	// Get thank-you notes for this submission. RLS returns only what the viewer
	// may see (their own as author, all as a vetter, approved as a recipient).
	const { data: thanks } =
		submission === null ? { data: null } : await db.getSubmissionThanks(submission.id);

	// Count active (uncompleted) approved assignments per candidate scholar on
	// this venue, so the cap-vs-load indicator can render "n / cap".
	const { data: venueAssignments } = await db.getVenueActiveAssignmentScholars(venueid);
	const venueActiveCounts: Record<string, number> = {};
	for (const row of venueAssignments ?? []) {
		venueActiveCounts[row.scholar] = (venueActiveCounts[row.scholar] ?? 0) + 1;
	}

	// Count active assignments per candidate scholar on OTHER venues (the
	// viewer can see; RLS gates anonymous venues outside their scope). Lets
	// the load indicator show overall workload alongside the cap-vs-load.
	const candidateIDs = [...new Set((assignments ?? []).map((a) => a.scholar))];
	const { data: allActive } =
		candidateIDs.length === 0
			? { data: [] }
			: await db.getActiveAssignmentsForScholars(candidateIDs);
	const elsewhereActiveCounts: Record<string, number> = {};
	for (const row of allActive ?? []) {
		if (row.venue === venueid) continue;
		elsewhereActiveCounts[row.scholar] = (elsewhereActiveCounts[row.scholar] ?? 0) + 1;
	}

	return {
		submission,
		venue,
		authors,
		previous: previous !== null && previous.length > 0 ? previous[0] : null,
		transactions,
		assignments,
		submissionHasEditor,
		volunteers,
		roles,
		balances,
		submissionTypes,
		assignmentScholars: assignmentScholars ?? [],
		preferenceLevels,
		venueActiveCounts,
		elsewhereActiveCounts,
		viewerVolunteering,
		thanks
	};
};
