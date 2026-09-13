/** How much of a role's volunteer roster this viewer is not being shown.
 *
 * The volunteers SELECT policy filters rows by each role's `volunteer_visibility`,
 * so the roster page renders a list that may be quietly partial — and a partial
 * list that looks complete is worse than a short one that says so. The true counts
 * come from `venue_volunteer_counts`, which is public whatever the roster says.
 *
 * A module rather than logic in the component, so the arithmetic can be tested
 * without one: the rule has two ways to go wrong that a rendered page hides.
 */

/** Only the fields this logic reads. */
export type CountedVolunteer = { roleid: string };

export type RoleWithholding = {
	/** How many volunteers the role really has. */
	total: number;
	/** How many of them this viewer may see. */
	visible: number;
	/** How many are not listed for this viewer. Never negative. */
	withheld: number;
	/** True when the viewer may see none of them — the roster is not short, it is
	 * absent, and the page has to say so rather than omit the role entirely. */
	all: boolean;
};

/** What this viewer is not being shown of one role's roster.
 *
 * `visible` is deliberately counted from the role's UNFILTERED rows, not from
 * whatever the search box and expertise chips have narrowed them to. Comparing
 * against the filtered rows would report a search as withholding, which is both
 * false and alarming.
 *
 * A missing count means the counts RPC did not load. That is not the same as zero:
 * report nothing withheld rather than claim a whole roster is hidden.
 */
export function withholdingFor(
	roleID: string,
	volunteers: CountedVolunteer[],
	counts: { role: string; volunteer_count: number }[] | null
): RoleWithholding {
	const visible = volunteers.filter((v) => v.roleid === roleID).length;
	const counted = counts?.find((c) => c.role === roleID)?.volunteer_count;
	const total = counted ?? visible;
	// Clamped at zero: a viewer can never see more rows than exist, but the count
	// and the rows are two round trips and a volunteer may leave between them.
	const withheld = Math.max(0, total - visible);
	return { total, visible, withheld, all: total > 0 && visible === 0 };
}

/** Whether any of the venue's roles is withholding anything from this viewer.
 *
 * Used to decide whether the CSV export has to warn that it is partial, and
 * whether "this venue has no volunteers" is still a true thing to say. */
export function anyWithheld(
	roleIDs: string[],
	volunteers: CountedVolunteer[],
	counts: { role: string; volunteer_count: number }[] | null
): boolean {
	return roleIDs.some((id) => withholdingFor(id, volunteers, counts).withheld > 0);
}
