import type { Breadcrumb } from '$lib/data/breadcrumbs';
import type { PageLoad } from './$types';

export const load: PageLoad = async ({ parent, params }) => {
	const { db, locale, scholar: viewedScholar } = await parent();

	// Get the scholar's most recent transactions.
	const { data: transactions, count } = await db.getScholarTransactions(params.id);

	const { data: venues } =
		transactions === null ? { data: null } : await db.getTransactionVenues(transactions);

	const { data: currencies } =
		transactions === null ? { data: null } : await db.getTransactionCurrencies(transactions);

	return {
		breadcrumbs: viewedScholar
			? ([
					[
						`/scholar/${viewedScholar.id}`,
						viewedScholar.name ??
							viewedScholar.orcid ??
							viewedScholar.email ??
							locale.page.scholar.title
					]
				] as Breadcrumb[])
			: [],
		transactions,
		venues,
		currencies,
		count
	};
};
