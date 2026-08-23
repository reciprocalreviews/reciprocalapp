import { articles } from '$routes/[[lang]]/help/articles';
import type { RequestHandler } from './$types';

/** A sitemap of the pages that are meant to be found.
 *
 * Generated per request rather than checked in, because two thirds of it moves:
 * venues are adopted and retired continuously, and a static file would advertise
 * the set of venues as of whenever someone last remembered to regenerate it.
 *
 * This route lives outside `[[lang]]` so its URL is stable, and the origin comes
 * from the request rather than a constant so staging maps itself rather than
 * production.
 *
 * Deliberately absent: scholar profiles. They carry a real person's name, their
 * ORCID, and their reviewing history, and while each is reachable by anyone with
 * the link, enumerating them for crawlers is a different act than publishing
 * them. Venues are institutions and are listed; people are not.
 */

/** Pages that exist regardless of what is in the database. `/login`, `/verify`,
 * and `/auth` are omitted to match static/robots.txt, and the authenticated
 * routes are omitted because a crawler only ever sees a redirect. */
const STATIC_PAGES = [
	{ path: '/', priority: '1.0', changefreq: 'monthly' },
	{ path: '/venues', priority: '0.9', changefreq: 'weekly' },
	{ path: '/about', priority: '0.7', changefreq: 'monthly' },
	{ path: '/help', priority: '0.7', changefreq: 'monthly' },
	{ path: '/contact', priority: '0.5', changefreq: 'yearly' },
	{ path: '/updates', priority: '0.5', changefreq: 'weekly' },
	{ path: '/terms', priority: '0.3', changefreq: 'yearly' },
	{ path: '/brand', priority: '0.3', changefreq: 'yearly' }
];

function entry(origin: string, path: string, priority: string, changefreq: string) {
	return `	<url>
		<loc>${escapeXML(origin + path)}</loc>
		<changefreq>${changefreq}</changefreq>
		<priority>${priority}</priority>
	</url>`;
}

/** A venue title never reaches this file, but a URL can carry `&`, and an
 * unescaped one makes the whole document unparseable rather than one entry
 * wrong. */
function escapeXML(text: string) {
	return text
		.replace(/&/g, '&amp;')
		.replace(/</g, '&lt;')
		.replace(/>/g, '&gt;')
		.replace(/"/g, '&quot;')
		.replace(/'/g, '&apos;');
}

export const GET: RequestHandler = async ({ url, locals, setHeaders }) => {
	const origin = url.origin;

	// A venue is active exactly when `inactive` is null; the rest are still
	// reachable but are being configured or have been retired, and pointing a
	// crawler at them advertises something that isn't running.
	const { data: venues } = await locals.supabase.from('venues').select('id').is('inactive', null);

	const entries = [
		...STATIC_PAGES.map((p) => entry(origin, p.path, p.priority, p.changefreq)),
		...articles.map((a) => entry(origin, `/help/${a.slug}`, '0.6', 'monthly')),
		// A failed query yields no venue entries rather than no sitemap: the static
		// pages are the half that search engines most need, and a 500 here would
		// cost us those too.
		...((venues ?? []) as { id: string }[]).map((venue) =>
			entry(origin, `/venue/${venue.id}`, '0.8', 'weekly')
		)
	];

	setHeaders({ 'cache-control': 'public, max-age=3600' });

	return new Response(
		`<?xml version="1.0" encoding="UTF-8" ?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${entries.join('\n')}
</urlset>`,
		{ headers: { 'content-type': 'application/xml' } }
	);
};
