import type { PageLoad } from './$types';

export const load: PageLoad = async ({ parent, params }) => {
	const { db, scholar: viewer } = await parent();

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
	const viewingSelf = viewer?.id === scholarID;
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

	// Get the scholar's approved reviewing assignments
	const { data: reviews } = await db.getScholarReviews(scholarID);

	// Get the roles for which the scholar is the role approver.
	const { data: approver } = await db.getRolesByApprover(reviews?.map((c) => c.role) || []);

	// Get the assignments for which the scholar is the role approver, to show in the scholar's dashboard.
	const { data: approvals } = await db.getAssignmentsForApproval(approver?.map((r) => r.id) || []);

	// Get completed work awaiting this approver's compensation decision. Without
	// this, the only notice was the one-shot CompensationRequested email.
	const { data: compensating } = await db.getAssignmentsAwaitingCompensation(
		approver?.map((r) => r.id) || []
	);

	// Which optional notices this scholar has silenced. The RLS policy admits only their
	// own rows, so this is empty when viewing someone else's profile — which is right,
	// since the controls are rendered only for the scholar themselves.
	const { data: notifications } = await db.getNotificationSettings(scholarID);

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
		reviews: reviews,
		approvals: approvals,
		compensating: compensating,
		notifications: notifications
	};
};
