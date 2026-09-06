/** The volunteers-list view logic: search matching, the expertise keywords the
 * list can be narrowed to, and the order the rows appear in.
 *
 * Extracted from the volunteers page so the ranking and the ordering can be
 * tested directly. Everything here is pure — the page's reactive reads are
 * passed in as a context object. */

import familyName from './familyName';

/** Only the volunteer fields the view logic reads. */
export type ViewVolunteer = {
	/** Free text. Comma-separated by convention only; nothing enforces it. */
	expertise: string;
	active: boolean;
	scholars: { name: string | null; email: string | null };
};

/** One expertise chip: the key it groups on, the spelling to show, and how many
 * of the search-matched volunteers claim it. */
export type ExpertiseTag = { key: string; label: string; count: number };

export type VolunteersViewContext = {
	/** The raw search box contents; trimmed and lowercased here. */
	filter: string;
	/** The selected expertise chips: the lowercased key each groups on, mapped to
	 * the label it carried when it was picked. Keyed rather than labelled so a
	 * selection survives a change in which spelling is commonest; the label is
	 * carried alongside so the chip the reader is holding never relabels underneath
	 * them — including when a search narrows its count to zero and there is no
	 * spelling left to derive one from. Empty means "no tag filter", not "match
	 * nothing". */
	selected: Map<string, string>;
};

/** How many chips to show before the list is folded behind "show all". */
export const TAG_LIMIT = 12;

/** One volunteer's expertise as tags: split on commas, trimmed, empties dropped.
 *
 * A free function rather than a method on the view, because the expertise column
 * renders the same tags with no filter or selection in play. */
export function expertiseTags(expertise: string): string[] {
	return expertise
		.split(',')
		.map((tag) => tag.trim())
		.filter((tag) => tag.length > 0);
}

/** Case is a spelling difference, not a different expertise, so "Peer Review"
 * and "peer review" group under one key. */
function keyOf(tag: string): string {
	return tag.toLowerCase();
}

/** The spelling to show for a tag: the one the most volunteers wrote, ties broken
 * alphabetically.
 *
 * Deliberately not "the first one seen". The commitments query has no `order by`
 * (see venueCommitmentsQuery in SupabaseCRUD), so row order is not guaranteed
 * between loads, and a label chosen by position could silently change from one
 * visit to the next. */
function bestSpelling(spellings: Map<string, number>): string {
	return [...spellings.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))[0][0];
}

export function volunteersView(context: VolunteersViewContext) {
	const trimmedFilter = context.filter.trim().toLowerCase();

	/** True if the given text contains the active filter term (case-insensitive). */
	function matches(text: string | null | undefined): boolean {
		return text !== null && text !== undefined && text.toLowerCase().includes(trimmedFilter);
	}

	/** An empty search keeps everyone; otherwise the three things the row shows —
	 * name, expertise, email — are what can be matched. */
	function matchesFilter(volunteer: ViewVolunteer): boolean {
		if (trimmedFilter === '') return true;
		return (
			matches(volunteer.scholars.name) ||
			matches(volunteer.expertise) ||
			matches(volunteer.scholars.email)
		);
	}

	/** Union, not intersection: an editor picking "HCI" and "education" is widening
	 * the net for a paper that touches both, not asking for the few people who
	 * claim both. */
	function matchesTags(volunteer: ViewVolunteer): boolean {
		if (context.selected.size === 0) return true;
		return expertiseTags(volunteer.expertise).some((tag) => context.selected.has(keyOf(tag)));
	}

	/** The expertise chips to offer, most claimed first.
	 *
	 * Counted over the volunteers the search box already matched — so the chips
	 * re-count as you type — but NOT over the current selection. Narrowing the
	 * chip list by its own selection collapses it to the chips you already picked,
	 * and there is then no way to add a second one. It also means toggling a chip
	 * never re-ranks the list, so chips do not jump out from under the pointer.
	 *
	 * A volunteer counts once per tag however many times they wrote it, so a
	 * chip's number is the number of rows selecting it alone would show. */
	function tags(volunteers: ViewVolunteer[]): ExpertiseTag[] {
		const counts = new Map<string, { count: number; spellings: Map<string, number> }>();
		for (const volunteer of volunteers) {
			if (!matchesFilter(volunteer)) continue;
			const countedKeys = new Set<string>();
			const countedSpellings = new Set<string>();
			for (const tag of expertiseTags(volunteer.expertise)) {
				const key = keyOf(tag);
				const entry = counts.get(key) ?? { count: 0, spellings: new Map<string, number>() };
				if (!countedKeys.has(key)) {
					entry.count += 1;
					countedKeys.add(key);
				}
				if (!countedSpellings.has(tag)) {
					entry.spellings.set(tag, (entry.spellings.get(tag) ?? 0) + 1);
					countedSpellings.add(tag);
				}
				counts.set(key, entry);
			}
		}

		// Ties broken on the key rather than the label, so the ranking cannot wobble
		// when the winning spelling changes. A selected chip keeps the label it was
		// picked with, for the same reason: the commonest spelling among the search's
		// matches is not the commonest spelling overall, so deriving it afresh would
		// relabel a control the reader is in the middle of using.
		const found = [...counts.entries()]
			.map(([key, { count, spellings }]) => ({
				key,
				label: context.selected.get(key) ?? bestSpelling(spellings),
				count
			}))
			.sort((a, b) => b.count - a.count || a.key.localeCompare(b.key));

		// A selected chip the current search counted out is kept, at zero, at the
		// end, under the label it has been wearing all along. Dropping it would
		// narrow the list by a criterion nothing on screen shows; unselecting it
		// would throw away a choice nobody undid.
		const missing = [...context.selected]
			.filter(([key]) => !counts.has(key))
			.sort((a, b) => a[0].localeCompare(b[0]))
			.map(([key, label]) => ({ key, label, count: 0 }));

		return [...found, ...missing];
	}

	/** The chips to render: the head of the ranked list, plus any selected chip the
	 * cap pushed out of it — a selection that cannot be seen cannot be undone. */
	function capped(tags: ExpertiseTag[], limit = TAG_LIMIT): ExpertiseTag[] {
		if (tags.length <= limit) return tags;
		return [
			...tags.slice(0, limit),
			...tags.slice(limit).filter((tag) => context.selected.has(tag.key))
		];
	}

	/** What the row actually shows: the name, or the email ScholarLink falls back to
	 * when a scholar has none. Ordering on the text on screen is what makes the
	 * order readable — ordering on `name` would sort a nameless scholar to the very
	 * top on an empty string, above every A. */
	function displayName(volunteer: ViewVolunteer): string {
		const name = (volunteer.scholars.name ?? '').trim();
		return name.length > 0 ? name : (volunteer.scholars.email ?? '');
	}

	/** Active first, then by family name. Someone who has stopped volunteering is
	 * still a permanent record of the venue, but they are not who an editor is
	 * scanning for, so they go last rather than interleaved. */
	function compare(a: ViewVolunteer, b: ViewVolunteer): number {
		if (a.active !== b.active) return a.active ? -1 : 1;
		const family = familyName(displayName(a)).localeCompare(familyName(displayName(b)));
		if (family !== 0) return family;
		const full = displayName(a).localeCompare(displayName(b));
		if (full !== 0) return full;
		return (a.scholars.email ?? '').localeCompare(b.scholars.email ?? '');
	}

	/** The rows one role's section shows, in the order it shows them. The search
	 * box and the expertise chips are ANDed. Returns a new array; the caller's is
	 * not mutated. */
	function sortedAndFiltered<T extends ViewVolunteer>(volunteers: T[]): T[] {
		return volunteers.filter((v) => matchesFilter(v) && matchesTags(v)).sort(compare);
	}

	return { matchesFilter, matchesTags, tags, capped, sortedAndFiltered };
}
