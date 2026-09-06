import type { LocaleText } from '$lib/locales/Locale';
import { venuePath } from './venuePath';

/**
 * One step of the trail shown in the nav, as a URL and the label to show for it.
 *
 * Breadcrumbs travel in load data rather than being handed up from the page through
 * context. They used to be set in an `$effect`, which does not run during SSR, so the
 * server HTML shipped a nav row without them and hydration inserted the chips — enough,
 * on a narrow screen, to wrap the row and shift the whole page down. Coming from a load
 * they are present in the first render, and they change atomically on navigation.
 */
export type Breadcrumb = [url: string, label: string];

/**
 * The trail to a venue: empty when no venue resolved, which is exactly the case in which
 * the page renders an "unknown venue" message and has nowhere to point.
 */
export function venueCrumbs(
	venue: { id: string; slug: string | null; title: string } | null | undefined
): Breadcrumb[] {
	return venue ? [[`/venue/${venuePath(venue)}`, venue.title]] : [];
}

/** The trail to a venue's submissions, for the pages that sit beneath it. */
export function submissionsCrumbs(
	venue: { id: string; slug: string | null; title: string } | null | undefined,
	locale: LocaleText
): Breadcrumb[] {
	return venue
		? [
				...venueCrumbs(venue),
				[`/venue/${venuePath(venue)}/submissions`, locale.page.submissions.title]
			]
		: [];
}
