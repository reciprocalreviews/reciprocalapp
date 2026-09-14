import type { ORCIDProfileRow } from '$data/types';
import type { ORCIDLink, ORCIDWork } from './orcidProfile';

/**
 * How a mirrored ORCID record reads on the page.
 *
 * Extracted from the components so the joining rules can be tested directly, which is the
 * same reason volunteersView.ts exists. Everything here is pure.
 *
 * Every function takes a possibly-absent, possibly-partial profile, because that is what
 * the callers actually hold: a scholar may have no row at all, list queries deliberately
 * omit the two jsonb columns to keep the payload small, and a partly-failed refresh leaves
 * some columns filled and others not.
 */

/** What a list query selects: everything but the two jsonb payloads. */
export type ProfileSummary = Partial<ORCIDProfileRow> | null | undefined;

/** Join the parts of a line, dropping the missing ones. Written once because doing it
 * inline is how you get a line that reads ", University of Washington" for somebody whose
 * record has an organization and no title. */
function join(parts: (string | null | undefined)[]): string | null {
	const present = parts
		.map((part) => part?.trim())
		.filter((part): part is string => part !== undefined && part.length > 0);
	return present.length > 0 ? present.join(', ') : null;
}

/** "Professor, The Information School, University of Washington".
 *
 * `short` drops the department, for the assignment table: it is the least discriminating
 * part and that is the narrowest cell on the page. */
export function affiliationLine(profile: ProfileSummary, short = false): string | null {
	if (!profile) return null;
	return join([
		profile.employment_role,
		short ? null : profile.employment_department,
		profile.employment_organization
	]);
}

/** "Ph.D. Human-Computer Interaction, Carnegie Mellon University, 2008". */
export function educationLine(profile: ProfileSummary): string | null {
	if (!profile) return null;
	return join([
		profile.education_role,
		profile.education_organization,
		profile.education_year === null || profile.education_year === undefined
			? null
			: String(profile.education_year)
	]);
}

/**
 * "46 works, 2004–2025".
 *
 * Null when the works section has not been read — which is NOT the same as a record with
 * no works, and the two must not render alike: one is RR not knowing, the other is a fact
 * about the scholar. A record read and found empty says "no works", not nothing.
 */
export function worksStat(profile: ProfileSummary): string | null {
	if (!profile) return null;
	const count = profile.work_count;
	if (count === null || count === undefined) return null;
	if (count === 0) return 'No works';

	const works = count === 1 ? '1 work' : `${count} works`;
	const first = profile.work_first_year;
	const last = profile.work_last_year;
	if (first === null || first === undefined || last === null || last === undefined) return works;
	// An en dash, and only when the years differ: "2024–2024" is a range nobody writes.
	return first === last ? `${works}, ${first}` : `${works}, ${first}–${last}`;
}

/** The works to render. Absent on a list query, which does not select the column. */
export function works(profile: ProfileSummary): ORCIDWork[] {
	const value = profile?.works;
	return Array.isArray(value) ? (value as unknown as ORCIDWork[]) : [];
}

export function links(profile: ProfileSummary): ORCIDLink[] {
	const value = profile?.links;
	return Array.isArray(value) ? (value as unknown as ORCIDLink[]) : [];
}

export function keywords(profile: ProfileSummary): string[] {
	return profile?.keywords ?? [];
}

/**
 * Whether there is anything worth showing.
 *
 * The predicate the whole section hangs on. A header with nothing under it tells a visitor
 * this person has no career, which is false — it means they made nothing public, or RR has
 * not read them yet. So absence renders as absence, and this is what decides it.
 *
 * `fetch_status` is deliberately not consulted: a row that failed to refresh but still
 * holds last month's affiliation is worth showing, and a row that succeeded and found
 * nothing is not.
 */
export function hasAnything(profile: ProfileSummary): boolean {
	if (!profile) return false;
	return (
		affiliationLine(profile) !== null ||
		educationLine(profile) !== null ||
		keywords(profile).length > 0 ||
		works(profile).length > 0 ||
		links(profile).length > 0 ||
		// A read record with zero works still says something: it is the difference between
		// "we have not looked" and "there is nothing there".
		(profile.work_count !== null && profile.work_count !== undefined)
	);
}

/**
 * Whether to tell the scholar themselves that RR could not read their record.
 *
 * Only ever shown to the scholar on their own profile. On a public page "their ORCID
 * record could not be found" reads as an accusation, and may only mean ORCID was down
 * when we asked — and the visitor can do nothing about it either way. The scholar can.
 */
export function shouldReportProblem(profile: ProfileSummary): boolean {
	return profile?.fetch_status === 'not_found' || profile?.fetch_status === 'error';
}
