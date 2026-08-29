import type { PageLoad } from './$types';

export const load: PageLoad = async ({ parent, params }) => {
	const { db } = await parent();

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

	// Get the scholar's current tokens.
	const { data: tokens } = await db.getScholarTokens(scholarID);

	// Get the currencies that the tokens use
	const currencyIDs = tokens ? tokens.map((t) => t.currency) : [];
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
		tokens: tokens,
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
