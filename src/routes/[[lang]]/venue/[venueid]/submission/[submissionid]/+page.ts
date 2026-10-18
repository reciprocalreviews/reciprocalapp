import { NO_VENUE_ID } from '#lib/data/venuePath.js';
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

	// Get the token balances of each volunteer and each assignee in the venue's currency, so we
	// can sort by them. Assignees too: a scholar can be assigned without ever volunteering, and
	// leaving them out showed their balance as 0 even after they were paid.
	const balanceScholarIDs = Array.from(
		new Set([
			...(volunteers ?? []).map((v) => v.scholarid),
			...(assignments ?? []).map((a) => a.scholar)
		])
	);
	const { data: balances } =
		venue === null ? { data: null } : await db.getTokenBalances(venue.currency, balanceScholarIDs);

	// Get the submission types in case we need to change it.
	const { data: submissionTypes } = await db.getVenueSubmissionTypes(venueid);

	// Names of scholars referenced by assignments, for stable sorting by family name.
	const assignmentScholarIDs = Array.from(new Set(assignments?.map((a) => a.scholar) ?? []));
	const { data: assignmentScholars } =
		assignmentScholarIDs.length === 0
			? { data: [] }
			: // Widened from getScholarNames to carry the mirrored ORCID columns the table
				// shows under each name. Same round trip: the profile travels as a PostgREST
				// embed, and a scholar RR has not read comes back with a null one.
				await db.getScholarCards(assignmentScholarIDs);

	// Contact addresses of everyone with an assignment here, accepted or still bidding, so an
	// approver can ask a bidder about their bid before accepting it and invite an accepted one
	// in a venue's own reviewing system. The page shows them only to approvers.
	const { data: assigneeEmails } =
		assignmentScholarIDs.length === 0
			? { data: [] }
			: await db.getScholarEmails(assignmentScholarIDs);

	// Get the venue's preference levels (may be empty) for rendering bid labels.
	const { data: preferenceLevels } = await db.getVenuePreferenceLevels(venueid);

	// Get thank-you notes for this submission. RLS returns only what the viewer
	// may see (their own as author, all as a vetter, approved as a recipient).
	const { data: thanks } =
		submission === null ? { data: null } : await db.getSubmissionThanks(submission.id);

	// How busy each candidate already is: their active assignments per role here, and in
	// other venues, for the indicator beside their cap. True counts, not RLS-limited ones,
	// which is what keeps an associate editor from seeing a full reviewer as free; the RPC
	// answers only the venue's admins and approvers, and nobody else sees the column.
	const candidateIDs = [...new Set((assignments ?? []).map((a) => a.scholar))];
	const { data: loads } = await db.getAssignmentLoads(venueid, candidateIDs);

	// Assignments the import could not match to a scholar on this submission. RLS shows
	// only the ones this viewer could approve, and an empty list otherwise.
	const { data: unmatched } =
		venue === null || submission === null
			? { data: [] }
			: await db.getUnmatchedAssignments(venue.id, submission.id);

	return {
		submission,
		venue,
		unmatched: unmatched ?? [],
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
		assigneeEmails: assigneeEmails ?? [],
		preferenceLevels,
		loads: loads ?? [],
		viewerVolunteering,
		thanks
	};
};
