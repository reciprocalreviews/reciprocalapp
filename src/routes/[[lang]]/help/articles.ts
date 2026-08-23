import manifest from './articles.json';

/**
 * The knowledge base lives in this repository as Markdown rather than in a wiki or a
 * vendor's help tool: it is versioned with the code that it describes, reviewed in pull
 * requests like anything else, and served from our own domain. The repository is also
 * the only durable storage the project has.
 */
export type Article = {
	slug: string;
	title: string;
	summary: string;
};

/** Article bodies, keyed by slug. Bundled at build time, so /help needs no database. */
const bodies: Record<string, string> = Object.fromEntries(
	Object.entries(
		import.meta.glob('./articles/*.md', {
			query: '?raw',
			import: 'default',
			eager: true
		}) as Record<string, string>
	).map(([path, body]) => [path.replace('./articles/', '').replace('.md', ''), body])
);

/** The manifest sets the order articles are listed in — most-asked first, not alphabetical. */
export const articles: Article[] = manifest;

export function getArticle(slug: string): (Article & { body: string }) | undefined {
	const article = articles.find((a) => a.slug === slug);
	const body = bodies[slug];
	// Both halves must exist: a manifest entry with no file would render an empty page,
	// and a file with no entry would be unreachable from the index anyway.
	return article && body ? { ...article, body } : undefined;
}
