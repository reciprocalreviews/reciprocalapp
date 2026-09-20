import type {
	AssignmentAwaitingCompensation,
	AssignmentForApproval,
	ScholarTask
} from '$lib/data/SupabaseCRUD.svelte';
import type { RoleID } from '$data/types';
import type { PageLoad } from './$types';

export const load: PageLoad = async ({ parent, params }) => {
	const { db, claims } = await parent();

	const scholarID = params.id;

	// Get the scholar's active commitments and pending invitations. Pending
	// invitations are active=false but accepted='invited', so we OR the filters
	// to include them; declined rows (active=false, accepted='declined') stay
	// excluded.
	const { data: volunteers } = await db.getScholarVolunteering(scholarID);

	const venueids = volunteers
		? volunteers.map((c) => c.roles?.venueid).filter((v) => v !== undefined)
		: [];

	const { data: venues } = venueids.length > 0 ? await db.getVenuesByIDs(venueids) : { data: [] };

	// Get the currencies for which the scholar is a minter
	const { data: minting } = await db.getScholarMintingCurrencies(scholarID);

	// Get the scholar's administered venues
	const { data: admins } = await db.getScholarAdminVenues(scholarID);

	// How many tokens the scholar holds, per currency, counted in the database —
	// and ONLY when you are looking at your own profile. Balances are private
	// (#109), and the RLS policy enforces that, so asking for someone else's would
	// return an empty map. That is not the same as "holds nothing", and the page
	// below rendered it as a confident "0 tokens" — which is what anonymous
	// visitors have always been shown. Not asking is how the page tells the
	// difference.
	//
	// The viewer is `claims.sub` from the ROOT layout, not the `scholar` row: this route's
	// own +layout.ts returns the VIEWED scholar under that same name and shadows it, so
	// `scholar.id === params.id` was true on every profile that loads at all. This gate
	// has therefore never fired. Nothing leaked — the RLS policy is what actually keeps
	// balances private — but the reads it was meant to skip were being made on every
	// visitor's view of every profile, and scholar_tasks below is not callable without a
	// session, so anonymous visitors logged a permission error for it.
	const viewingSelf = claims?.sub === scholarID;
	const { data: balances } = viewingSelf
		? await db.getScholarBalances(scholarID)
		: { data: {} as Record<string, number> };

	// Get the currencies that the tokens use
	const currencyIDs = Object.keys(balances);
	const { data: currencies } = await db.getCurrenciesByIDs(currencyIDs);

	// Get the scholar's most recent transactions.
	const { data: transactions } = await db.getScholarTransactionCount(scholarID);

	// Get pending transactions on currencies for which the scholar is a minter
	const { data: pending } = await db.getPendingTransactionsByCurrencies(
		minting ? minting.map((c) => c.id) : []
	);

	// Get proposed transactions where the scholar is the source
	const { data: outgoingPending } = await db.getOutgoingPendingTransactions(scholarID);

	// Get the scholar's submissions
	const { data: submissions } = await db.getScholarSubmissions(scholarID);

	// The work actually waiting on this scholar. The four reads below all answer for
	// auth.uid(), not for the profile being viewed, and Scholar.svelte draws the Tasks
	// table only on your own profile — so asking on someone else's spent four round
	// trips building a table nobody sees. Same reasoning as the balances read above.
	const { data: tasks } = viewingSelf ? await db.getScholarTasks() : { data: [] as ScholarTask[] };

	// The roles for which the scholar is the role approver. Deliberately NOT derived
	// from `tasks`: this used to be `getRolesByApprover(reviews.map(c => c.role))` over
	// the very array the table rendered, so narrowing what is displayed silently deleted
	// the two approver rows below. They are different questions; they now have separate
	// answers. See public.scholar_approver_roles.
	const { data: approver } = viewingSelf
		? await db.getScholarApproverRoles()
		: { data: [] as { role: RoleID }[] };
	const approverRoles = approver?.map((r) => r.role) ?? [];

	// Get the assignments for which the scholar is the role approver, to show in the scholar's dashboard.
	const { data: approvals } = viewingSelf
		? await db.getAssignmentsForApproval(approverRoles)
		: { data: [] as AssignmentForApproval[] };

	// Get completed work awaiting this approver's compensation decision. Without
	// this, the only notice was the one-shot CompensationRequested email.
	const { data: compensating } = viewingSelf
		? await db.getAssignmentsAwaitingCompensation(approverRoles)
		: { data: [] as AssignmentAwaitingCompensation[] };

	// Which optional notices this scholar has silenced. The RLS policy admits only their
	// own rows, so this is empty when viewing someone else's profile — which is right,
	// since the controls are rendered only for the scholar themselves.
	const { data: notifications } = await db.getNotificationSettings(scholarID);

	// What, if anything, this scholar is waiting to verify (#27). Only when they are
	// looking at their own profile: the RPC answers for auth.uid() regardless of whose
	// page is open, so asking on someone else's would spend a round trip to render
	// nothing. Read here rather than in the component so the pending notice is in the
	// first byte, with no flash of "nothing pending" on the way.
	const { data: pendingEmail } = viewingSelf
		? await db.getPendingEmailVerification()
		: { data: null };

	return {
		commitments: volunteers,
		venues,
		admins: admins,
		balances,
		transactions: transactions,
		submissions: submissions,
		currencies: currencies,
		minting: minting,
		pending: pending,
		outgoingPending: outgoingPending,
		tasks: tasks,
		approvals: approvals,
		compensating: compensating,
		notifications: notifications,
		pendingEmail
	};
};
