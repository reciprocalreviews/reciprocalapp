import type { Breadcrumb } from '$lib/data/breadcrumbs';
import { error } from '@sveltejs/kit';
import { getArticle } from '../articles';
import type { PageLoad } from './$types';

export const load: PageLoad = async ({ parent, params }) => {
	const { locale } = await parent();
	const article = getArticle(params.slug);
	// A 404 rather than an empty page: an article that used to exist and no longer does
	// should say so, and a mistyped URL should not look like a broken article.
	if (article === undefined) error(404, 'No such help article');
	return {
		breadcrumbs: [['/help', locale.page.help.title]] as Breadcrumb[],
		article
	};
};
