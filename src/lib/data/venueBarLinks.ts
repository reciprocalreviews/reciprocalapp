import type { LocaleText } from '$lib/locales/Locale';
import { venuePath } from './venuePath';

/**
 * What the venue bar offers on a route inside a venue.
 *
 * The bar replaced a per-page title band that mostly restated the section name a reader
 * had just clicked (#176). What it costs in exchange is a set of gates — a payment-free
 * venue has no transactions worth showing, settings belong to admins, and a venue that
 * never named its website has no website link — and gates are exactly the kind of rule
 * that regresses quietly inside a component where nothing can reach it. So the decision
 * lives here and the component renders what it returns, the same arrangement
 * `canViewSubmission` and `sortSubmissions` already use.
 *
 * The labels are the destination pages' own titles rather than strings of the bar's own,
 * so a renamed page renames its link and the two can never disagree.
 *
 * The array is in the order the bar gives them up. `Overflow` collapses from the END, so
 * this order IS the rule about which links a narrow screen keeps longest — there is no
 * flag saying so, because a flag and an order would be two statements of one fact and they
 * would drift.
 */

export type VenueBarLink = {
	/** Where it goes. An absolute app path, or an external URL for the venue's own site. */
	href: string;
	label: string;
	/** True for the venue's own website, which leaves the app. */
	external: boolean;
};

export type VenueBarVenue = {
	id: string;
	slug: string | null;
	title: string;
	short_title: string;
	url: string;
	payment_free: boolean;
	admins: string[];
};

/** What the bar calls the venue: its short name when it has chosen one, its full title
 * otherwise. Empty is the unset state for `short_title`, so this needs no null check. */
export function venueBarName(venue: Pick<VenueBarVenue, 'title' | 'short_title'>): string {
	return venue.short_title.length > 0 ? venue.short_title : venue.title;
}

export function venueBarLinks(
	venue: VenueBarVenue,
	scholarID: string | null,
	locale: LocaleText
): VenueBarLink[] {
	const path = `/venue/${venuePath(venue)}`;
	const isAdmin = scholarID !== null && venue.admins.includes(scholarID);

	const links: VenueBarLink[] = [
		{
			href: `${path}/submissions`,
			label: locale.page.submissions.title,
			external: false
		},
		{
			href: `${path}/volunteers`,
			label: locale.page.volunteers.title,
			external: false
		}
	];

	// A payment-free venue hides every token, cost and compensation surface, so a link to
	// its ledger would lead to a page about a currency it does not use.
	if (!venue.payment_free)
		links.push({
			href: `${path}/transactions`,
			label: locale.page.venueTransactions.title,
			external: false
		});

	// Everyone else gets a page that only says they may not be here.
	if (isAdmin)
		links.push({
			href: `${path}/settings`,
			label: locale.page.settings.title,
			external: false
		});

	// A venue that has not said where it lives has nothing to point at, and `url` defaults
	// to the empty string rather than to null.
	if (venue.url.length > 0)
		links.push({
			href: venue.url,
			label: locale.page.venue.bar.website,
			external: true
		});

	return links;
}
