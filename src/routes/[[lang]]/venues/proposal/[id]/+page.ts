import type { PageLoad } from './$types.js';

export const load: PageLoad = async ({ parent, params }) => {
	const { db } = await parent();

	const { data: proposal } = await db.getProposal(params.id);

	const { data: supporters } = await db.getProposalSupporters(params.id);

	return {
		proposal: proposal ? proposal : null,
		supporters: supporters ? supporters : null
	};
};
