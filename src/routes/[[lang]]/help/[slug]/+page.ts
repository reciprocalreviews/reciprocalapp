import { error } from '@sveltejs/kit';
import { getArticle } from '../articles';
import type { PageLoad } from './$types';

export const load: PageLoad = async ({ params }) => {
	const article = getArticle(params.slug);
	// A 404 rather than an empty page: an article that used to exist and no longer does
	// should say so, and a mistyped URL should not look like a broken article.
	if (article === undefined) error(404, 'No such help article');
	return { article };
};
