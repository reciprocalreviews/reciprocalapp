import type { PageLoad } from './$types.js';

export const load: PageLoad = async ({ parent, params }) => {
	const { db } = await parent();

	const { data: proposal } = await db.getProposal(params.id);

	const { data: supporters } = await db.getProposalSupporters(params.id);

	// Which listed addresses no account uses yet. Approval no longer fails over these — the
	// editors who have accounts become the admins, and the approving steward holds the currency
	// if no proposed minter has one — but a steward deciding whether to approve should be able
	// to see what approving will actually produce.
	const { data: unknownAddresses } = proposal
		? await db.findUnknownAddresses([...proposal.editors, ...proposal.minters])
		: { data: [] };

	return {
		proposal: proposal ? proposal : null,
		supporters: supporters ? supporters : null,
		unknownAddresses: unknownAddresses ?? []
	};
};
