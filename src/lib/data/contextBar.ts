import { ScholarLabel, TokenLabel, VenueLabel } from '#lib/components/Labels.js';
import type { LocaleText } from '#lib/locales/Locale.js';

/**
 * The teal bar under the nav that says where you are and reaches the rest of that area.
 *
 * Inside a venue it has always been the venue bar (#176). Every other page used to carry
 * a sticky title band instead, so the app had two kinds of chrome and two heading
 * treatments; now every page's title sits in its text column and every page has one of
 * these. Which bar a route gets, and what it offers, are rules, and rules in this codebase
 * live where a unit test can reach them.
 *
 * It also replaced the breadcrumbs that used to trail the nav: the only places they went —
 * a scholar, a currency, the help index — are what these bars name.
 */

export type BarLink = {
	/** An absolute app path, or an external URL. */
	href: string;
	label: string;
	/** True for a link that leaves the app. */
	external: boolean;
};

export type Bar = {
	/** The glyph after the name, which says what kind of area this is. */
	icon: string;
	/** What the area is called — a scholar's name, a currency's, or a section's. */
	name: string;
	/** Where the name links: the area's own landing page. */
	href: string;
	/** In the order a narrow screen gives them up; the last collapses first. */
	links: BarLink[];
};

/** Pages about the platform itself, and anything not inside another area. */
export function siteBar(locale: LocaleText): Bar {
	return {
		icon: '',
		name: locale.page.home.title,
		href: '/',
		links: [
			{ href: '/about', label: locale.footer.link.about, external: false },
			{ href: '/help', label: locale.footer.link.help, external: false },
			{ href: '/contact', label: locale.footer.link.contact, external: false },
			{ href: '/updates', label: locale.footer.link.updates, external: false }
		]
	};
}

/** The venue list and venue proposals. Proposing needs an account, so the link waits for one. */
export function venuesBar(locale: LocaleText, signedIn: boolean): Bar {
	return {
		icon: VenueLabel,
		name: locale.page.venues.title,
		href: '/venues',
		links: signedIn
			? [{ href: '/venues/proposal', label: locale.page.venues.link.propose, external: false }]
			: []
	};
}

/** A scholar's profile and their transactions. */
export function scholarBar(
	scholar: { id: string; name: string | null; orcid: string | null },
	locale: LocaleText
): Bar {
	const href = `/scholar/${scholar.id}`;
	return {
		icon: ScholarLabel,
		name: scholar.name ?? scholar.orcid ?? locale.page.scholar.title,
		href,
		links: [
			{
				href: `${href}/transactions`,
				label: locale.page.scholarTransactions.title,
				external: false
			}
		]
	};
}

/** A currency and its transactions. */
export function currencyBar(currency: { id: string; name: string }, locale: LocaleText): Bar {
	const href = `/currency/${currency.id}`;
	return {
		icon: TokenLabel,
		name: currency.name,
		href,
		links: [
			{
				href: `${href}/transactions`,
				label: locale.page.currencyTransactions.title,
				external: false
			}
		]
	};
}

/**
 * Whether an area layout draws this route's bar, so the root layout should not. Exactly one
 * bar may render per route: each measures itself into `--page-header-height`, and two
 * observers on one property fight. `null` is an error page, which gets the site bar.
 */
export function areaDrawsBar(routeID: string | null): boolean {
	if (routeID === null) return false;
	return ['/[[lang]]/venue/', '/[[lang]]/venues', '/[[lang]]/scholar/', '/[[lang]]/currency/'].some(
		(prefix) => routeID.startsWith(prefix)
	);
}
