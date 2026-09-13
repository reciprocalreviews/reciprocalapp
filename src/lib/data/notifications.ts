import type { Notification } from './CRUD';

/**
 * How a batch of notifications becomes a readable number of banners.
 *
 * `handle()` used to post one banner per `notified` entry, which is right for the one or two
 * recipients most actions have and catastrophic for the ones that fan out: a call for bids to a
 * three-hundred-volunteer role produced three hundred banners in the sticky header, each needing
 * its own click to dismiss, with the page content pushed below all of them.
 *
 * RR had already decided this question for email — "a bulk import sends one message rather than
 * one per row; two hundred imported manuscripts are one piece of news, not two hundred" — and
 * `bulkImportSubmissions` implements it. This is the same rule applied to what the interface
 * says back.
 *
 * The rules live here rather than in `feedback.svelte.ts` so they can be tested without a
 * component or a stubbed `$app/navigation`, the way `volunteersView` and `inviteList` are.
 */

/**
 * How many notifications of one kind are shown individually before they collapse into one.
 *
 * Three, because naming people is the point below that: inviting two or three scholars to a role
 * and seeing each of them confirmed is the case the per-recipient banners were built for. Above
 * it the names stop being readable anyway, and a count says the same thing in one line.
 */
export const GROUP_MAX = 3;

/** One banner: a message, and — only when its producer supplied no plural form — how many
 * further notifications it stands for. */
export type CollapsedNotification = {
	message: string;
	/** The REST of the group, for the fallback rendering only. Absent both on a banner that
	 * stands only for itself and on a collapsed one whose producer wrote a plural form, since
	 * that form already states the number. Never 0. */
	others?: number;
};

/**
 * Collapse a batch of notifications into the banners to show for it.
 *
 * Entries carrying the same `group` are one piece of news. A group of `max` or fewer is shown
 * one banner each; a larger one becomes a single banner naming its first notification and
 * counting the rest.
 *
 * Three properties are load-bearing:
 *
 * - **Entries with no `group` always stand alone.** Grouping is opt-in, so a producer that has
 *   not thought about batching behaves exactly as it did before.
 * - **Distinct groups stay distinct.** Creating a submission charges its co-authors *and* tells
 *   an editor, which is two pieces of news; merging them by count alone would lose one.
 * - **A non-empty batch always yields at least one banner.** Only two of the app's `handle()`
 *   call sites pass a success string, so for everything else these notifications are the sole
 *   evidence that anything happened — collapsing to nothing would make a completed action look
 *   like a click that did nothing.
 *
 * Order is first appearance: a collapsed group sits where its first notification did, so the
 * banners stay in the order the action produced them.
 */
export function collapseNotifications(
	notified: Notification[],
	max: number = GROUP_MAX
): CollapsedNotification[] {
	// Count each group first, because whether the first entry of a group is shown on its own
	// depends on how many follow it — which is not known until the whole batch has been seen.
	const sizes = new Map<string, number>();
	for (const note of notified)
		if (note.group !== undefined) sizes.set(note.group, (sizes.get(note.group) ?? 0) + 1);

	const banners: CollapsedNotification[] = [];
	const collapsed = new Set<string>();

	for (const note of notified) {
		const size = note.group === undefined ? 1 : (sizes.get(note.group) ?? 1);

		if (note.group === undefined || size <= max) {
			banners.push({ message: note.message });
			continue;
		}

		// A large group contributes exactly one banner, at the position of its first entry.
		if (collapsed.has(note.group)) continue;
		collapsed.add(note.group);

		const rest = size - 1;

		// The producer's own plural reads properly — "Rigor Russ and 306 others were emailed
		// …" — because only it can change the verb and only it has locale. Falling back to the
		// singular plus a count is worse prose but still true; what neither may do is show the
		// first message alone, which would speak for 306 people without mentioning them.
		if (note.collapsed !== undefined)
			banners.push({ message: note.collapsed.replaceAll('{count}', rest.toString()) });
		else banners.push({ message: note.message, others: rest });
	}

	return banners;
}
