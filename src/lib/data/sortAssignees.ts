import familyName from './familyName';

/** The per-page lookups these sorts need, injected so the ordering rules can be
 * tested without a venue, a database, or a rendered component. */
export type AssigneeContext = {
	/** Token balance for a scholar in the venue's currency; 0 when unknown. */
	getBalance: (scholarID: string) => number;
	/** Display name for a scholar; '' when unknown. */
	nameOf: (scholarID: string) => string;
};

/** Only the fields the ordering depends on, so callers can pass full
 * PreferenceLevelRows and tests can pass two-field literals. */
export type PreferenceRank = { id: string; rank: number };

/** Compare two scholars by token balance (ascending — lowest balance first,
 * since the undercompensated are the ones most in need of paid work, per the
 * venue balance guidance in DESIGN.md #93), then family name (ascending).
 * The shared tail of both sorts below. */
function compareByBalanceThenName(a: string, b: string, context: AssigneeContext): number {
	const balanceDiff = context.getBalance(a) - context.getBalance(b);
	if (balanceDiff !== 0) return balanceDiff;
	return familyName(context.nameOf(a)).localeCompare(familyName(context.nameOf(b)));
}

/** Sort assignments by token balance (ascending), then by family name
 * (ascending). Returns a new array; doesn't mutate the input. */
export function sortAssignees<T extends { scholar: string }>(
	items: T[],
	context: AssigneeContext
): T[] {
	return [...items].sort((a, b) => compareByBalanceThenName(a.scholar, b.scholar, context));
}

/** Sort bids: lowest-rank preference (most preferred) first, then by balance
 * ascending, then by family name. Unset and unresolvable preferences sort last.
 *
 * The ranks are compared for equality rather than subtracted. An unset
 * preference is represented by Infinity, and subtracting two of those yields
 * NaN — which is not `!== 0`-false, so the comparator returned NaN and neither
 * tiebreaker ever ran. That made bid order arbitrary for any venue with no
 * preference levels configured, which is the default. */
export function sortBids<T extends { scholar: string; preferenceid: string | null }>(
	items: T[],
	context: AssigneeContext & { preferenceLevels: PreferenceRank[] | null | undefined }
): T[] {
	const rankFor = (preferenceid: string | null): number => {
		if (preferenceid === null) return Number.POSITIVE_INFINITY;
		return (
			context.preferenceLevels?.find((l) => l.id === preferenceid)?.rank ?? Number.POSITIVE_INFINITY
		);
	};
	return [...items].sort((a, b) => {
		const rankA = rankFor(a.preferenceid);
		const rankB = rankFor(b.preferenceid);
		if (rankA !== rankB) return rankA < rankB ? -1 : 1;
		return compareByBalanceThenName(a.scholar, b.scholar, context);
	});
}
