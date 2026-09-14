/**
 * Reading ORCID's public record into the narrow slice RR mirrors.
 *
 * This file lives beside the edge functions because Deno only bundles what is under
 * supabase/functions, and the `orcid` function is what fetches. It is re-exported from
 * src/lib/data/orcidProfile.ts so application code and the unit tests — which vitest
 * only collects from `src/**\/*.unit.ts` — import it from one place. Mirrors
 * _shared/emailShell.ts.
 *
 * Everything here is PURE and dependency-free: no Deno globals, no `$lib` imports, no
 * fetching. That is what lets vitest run it, and it is a constraint rather than a
 * preference — a Deno global here breaks the Vite build of the whole app.
 *
 * What RR takes, and what it deliberately leaves: see DESIGN.md's Scholar route section.
 * The short version is that this reads affiliation, keywords, recent works and education,
 * and reads no email (RR verifies its own, #27), no address, no biography, and no
 * peer-review records (too sparse to be informative; an empty section is read as a claim
 * about the person).
 */

/** The ORCID public API. No token and no client registration are required for
 * public-visibility data, which is the only data it returns. */
export const ORCID_PUBLIC_API = 'https://pub.orcid.org/v3.0';

/** The sections RR reads. `/record` would fetch all of them in one request, but it is
 * dominated by works — 87KB against 8.3KB for the other three combined — and works are
 * on a slower clock than the rest, so they are fetched separately. */
export type ORCIDSection = 'person' | 'employments' | 'educations' | 'works';

export function orcidAPIURL(id: string, section: ORCIDSection): string {
	return `${ORCID_PUBLIC_API}/${id}/${section}`;
}

/** How many works are kept. The rest of the record is reduced to a count and a span:
 * an assigner is scanning for topical fit, and five recent titles answer that better
 * than a bibliography they would have to read past. */
export const MAX_WORKS = 5;

export type ORCIDWork = {
	title: string;
	/** Null where the record gives no publication date, which is common on works
	 * imported from a source that had none. */
	year: number | null;
	journal: string | null;
	doi: string | null;
	url: string | null;
};

export type ORCIDLink = {
	kind: 'url' | 'identifier';
	label: string;
	value: string;
	url: string | null;
};

export type ORCIDProfile = {
	employmentRole: string | null;
	employmentDepartment: string | null;
	employmentOrganization: string | null;
	educationRole: string | null;
	educationOrganization: string | null;
	educationYear: number | null;
	keywords: string[];
	works: ORCIDWork[];
	/** Counted over every work in the record, not over the `works` kept above. Null
	 * means the works section was not read; 0 means it was read and is empty. The
	 * interface must not conflate the two. */
	workCount: number | null;
	workFirstYear: number | null;
	workLastYear: number | null;
	links: ORCIDLink[];
};

/** An empty profile, so a record with nothing public still parses to a well-formed
 * value rather than to null. `hasAnything` in orcidProfileView is what decides whether
 * such a profile is worth rendering. */
export function emptyProfile(): ORCIDProfile {
	return {
		employmentRole: null,
		employmentDepartment: null,
		employmentOrganization: null,
		educationRole: null,
		educationOrganization: null,
		educationYear: null,
		keywords: [],
		works: [],
		workCount: null,
		workFirstYear: null,
		workLastYear: null,
		links: []
	};
}

// ---------------------------------------------------------------------------
// ORCID's JSON shape
//
// Almost every scalar arrives wrapped as `{ "value": ... }`, and almost every wrapper
// can itself be null. The helpers below are deliberately total: they take `unknown` and
// answer with a value or null, so a shape change upstream degrades one field rather
// than throwing inside a batch and losing the other scholars in it.

type Json = Record<string, unknown>;

function obj(node: unknown): Json | null {
	return typeof node === 'object' && node !== null && !Array.isArray(node) ? (node as Json) : null;
}

function arr(node: unknown): unknown[] {
	return Array.isArray(node) ? node : [];
}

/** Unwrap `{ value: "x" }`. Trims, and treats an empty string as absent — ORCID records
 * carry plenty of whitespace-only fields, and a blank line on a profile is worse than
 * a missing one. */
function text(node: unknown): string | null {
	const wrapper = obj(node);
	if (wrapper === null) return null;
	const value = wrapper['value'];
	if (typeof value !== 'string') return null;
	const trimmed = value.trim();
	return trimmed.length > 0 ? trimmed : null;
}

/** The year out of an ORCID date. Years arrive as STRINGS (`"2008"`), and month and day
 * are independently nullable, so a date with only a year is both valid and common. */
function year(node: unknown): number | null {
	const date = obj(node);
	if (date === null) return null;
	const value = text(date['year']);
	if (value === null) return null;
	const parsed = Number.parseInt(value, 10);
	return Number.isFinite(parsed) ? parsed : null;
}

// ---------------------------------------------------------------------------
// Person: keywords and outbound links

/** Keywords, de-duplicated case-insensitively but shown in the spelling the record
 * uses. ORCID does not stop someone entering the same term twice. */
function parseKeywords(person: Json): string[] {
	const keywords: string[] = [];
	const seen = new Set<string>();
	for (const entry of arr(obj(person['keywords'])?.['keyword'])) {
		const content = obj(entry)?.['content'];
		const value = typeof content === 'string' ? content.trim() : null;
		if (value === null || value.length === 0) continue;
		const key = value.toLowerCase();
		if (seen.has(key)) continue;
		seen.add(key);
		keywords.push(value);
	}
	return keywords;
}

function parseLinks(person: Json): ORCIDLink[] {
	const links: ORCIDLink[] = [];

	for (const entry of arr(obj(person['researcher-urls'])?.['researcher-url'])) {
		const node = obj(entry);
		if (node === null) continue;
		const url = text(node['url']);
		if (url === null) continue;
		const name = typeof node['url-name'] === 'string' ? node['url-name'].trim() : '';
		links.push({
			kind: 'url',
			// A url with no name is shown as itself rather than as a blank link.
			label: name.length > 0 ? name : url,
			value: url,
			url
		});
	}

	for (const entry of arr(obj(person['external-identifiers'])?.['external-identifier'])) {
		const node = obj(entry);
		if (node === null) continue;
		const type =
			typeof node['external-id-type'] === 'string' ? node['external-id-type'].trim() : '';
		const value =
			typeof node['external-id-value'] === 'string' ? node['external-id-value'].trim() : '';
		if (type.length === 0 || value.length === 0) continue;
		links.push({ kind: 'identifier', label: type, value, url: text(node['external-id-url']) });
	}

	return links;
}

export function parsePerson(payload: unknown): Pick<ORCIDProfile, 'keywords' | 'links'> {
	const person = obj(payload);
	if (person === null) return { keywords: [], links: [] };
	return { keywords: parseKeywords(person), links: parseLinks(person) };
}

// ---------------------------------------------------------------------------
// Affiliations

type Affiliation = {
	role: string | null;
	department: string | null;
	organization: string | null;
	start: number | null;
	end: number | null;
};

/** Flatten ORCID's affiliation-group → summaries → {kind}-summary nesting. */
function affiliations(payload: unknown, kind: 'employment' | 'education'): Affiliation[] {
	const found: Affiliation[] = [];
	for (const group of arr(obj(payload)?.['affiliation-group'])) {
		for (const wrapper of arr(obj(group)?.['summaries'])) {
			const summary = obj(obj(wrapper)?.[`${kind}-summary`]);
			if (summary === null) continue;
			const role = typeof summary['role-title'] === 'string' ? summary['role-title'].trim() : '';
			const department =
				typeof summary['department-name'] === 'string' ? summary['department-name'].trim() : '';
			found.push({
				role: role.length > 0 ? role : null,
				department: department.length > 0 ? department : null,
				organization: (() => {
					const name = obj(summary['organization'])?.['name'];
					const value = typeof name === 'string' ? name.trim() : '';
					return value.length > 0 ? value : null;
				})(),
				start: year(summary['start-date']),
				end: year(summary['end-date'])
			});
		}
	}
	return found;
}

/**
 * The affiliation to show, of however many the record holds.
 *
 * A current post beats a past one however recent the past one is — someone who left a
 * more prestigious job last year is not there now, and an assigner reading the line is
 * asking where they are. "Current" means no end date, which is how ORCID represents an
 * ongoing role. Among current posts the latest start wins; among ended ones, the latest
 * end. Ties fall back to declaration order, which is stable within one response.
 */
function currentAffiliation(found: Affiliation[]): Affiliation | null {
	if (found.length === 0) return null;
	const open = found.filter((a) => a.end === null);
	const pool = open.length > 0 ? open : found;
	const key = open.length > 0 ? 'start' : 'end';
	let best = pool[0];
	for (const candidate of pool.slice(1)) {
		const a = candidate[key];
		const b = best[key];
		// A dated entry beats an undated one; otherwise the later date wins.
		if (a !== null && (b === null || a > b)) best = candidate;
	}
	return best;
}

export function parseEmployments(
	payload: unknown
): Pick<ORCIDProfile, 'employmentRole' | 'employmentDepartment' | 'employmentOrganization'> {
	const current = currentAffiliation(affiliations(payload, 'employment'));
	return {
		employmentRole: current?.role ?? null,
		employmentDepartment: current?.department ?? null,
		employmentOrganization: current?.organization ?? null
	};
}

export function parseEducations(
	payload: unknown
): Pick<ORCIDProfile, 'educationRole' | 'educationOrganization' | 'educationYear'> {
	const current = currentAffiliation(affiliations(payload, 'education'));
	return {
		educationRole: current?.role ?? null,
		educationOrganization: current?.organization ?? null,
		// The end date is when the degree was awarded; a study still in progress has
		// only a start, and that is the honest year to show for it.
		educationYear: current?.end ?? current?.start ?? null
	};
}

// ---------------------------------------------------------------------------
// Works

/** The DOI out of a group's or a summary's external ids. */
function doiOf(node: unknown): string | null {
	for (const entry of arr(obj(node)?.['external-id'])) {
		const id = obj(entry);
		if (id === null) continue;
		const type = typeof id['external-id-type'] === 'string' ? id['external-id-type'] : '';
		if (type.toLowerCase() !== 'doi') continue;
		const value = typeof id['external-id-value'] === 'string' ? id['external-id-value'].trim() : '';
		if (value.length > 0) return value;
	}
	return null;
}

/**
 * How complete a summary is, for picking between the several a group can hold.
 *
 * A work claimed by Crossref, by Scopus and by the scholar appears three times in one
 * group, and the copies differ: the observed case has Crossref carrying no journal title
 * where the scholar's own entry does. So the pick is by how much of what RR displays the
 * copy actually has, and only then by put-code, which breaks the tie deterministically
 * — row order within a group is not guaranteed between responses.
 */
function completeness(summary: Json): number {
	let score = 0;
	if (year(summary['publication-date']) !== null) score += 4;
	if (text(summary['journal-title']) !== null) score += 2;
	if (doiOf(summary['external-ids']) !== null) score += 1;
	return score;
}

function putCode(summary: Json): number {
	const value = summary['put-code'];
	return typeof value === 'number' ? value : Number.MAX_SAFE_INTEGER;
}

function preferredSummary(group: Json): Json | null {
	const summaries = arr(group['work-summary'])
		.map(obj)
		.filter((s): s is Json => s !== null);
	if (summaries.length === 0) return null;
	let best = summaries[0];
	for (const candidate of summaries.slice(1)) {
		const a = completeness(candidate);
		const b = completeness(best);
		if (a > b || (a === b && putCode(candidate) < putCode(best))) best = candidate;
	}
	return best;
}

/**
 * The works section: the most recent few, and a count and span over all of them.
 *
 * The count is the number of GROUPS, not the number of summaries. Each group is one
 * work, however many sources claimed it — a real record measured here holds 46 works
 * across 50 summaries, so counting summaries would have reported a number nine per cent
 * too high, and visibly wrong to the person it describes.
 */
export function parseWorks(
	payload: unknown
): Pick<ORCIDProfile, 'works' | 'workCount' | 'workFirstYear' | 'workLastYear'> {
	const groups = arr(obj(payload)?.['group']);

	const parsed: ORCIDWork[] = [];
	for (const entry of groups) {
		const group = obj(entry);
		if (group === null) continue;
		const summary = preferredSummary(group);
		if (summary === null) continue;
		const title = text(obj(summary['title'])?.['title']);
		if (title === null) continue;
		// The group's external ids are the union across its summaries, so a DOI can be
		// there when the chosen summary has none of its own.
		const doi = doiOf(summary['external-ids']) ?? doiOf(group['external-ids']);
		parsed.push({
			title,
			year: year(summary['publication-date']),
			journal: text(summary['journal-title']),
			doi,
			// A DOI resolves to the publisher's page, so it is the better link when there
			// is one; the record's own url is the fallback.
			url: doi !== null ? `https://doi.org/${doi}` : text(summary['url'])
		});
	}

	const years = parsed.map((work) => work.year).filter((y): y is number => y !== null);

	return {
		// Newest first, and undated works last rather than sorted as though they were
		// year zero. Sorted before slicing, so "recent" means recent in the record and
		// not merely first in whatever order ORCID answered in.
		works: [...parsed]
			.sort((a, b) => (b.year ?? -Infinity) - (a.year ?? -Infinity))
			.slice(0, MAX_WORKS),
		workCount: groups.length,
		workFirstYear: years.length > 0 ? Math.min(...years) : null,
		workLastYear: years.length > 0 ? Math.max(...years) : null
	};
}

/** Assemble a profile from the section payloads. Any section may be omitted — a refresh
 * where one request failed keeps whatever the others returned rather than blanking the
 * lot, and a routine refresh deliberately omits works, which are on a slower clock. */
export function buildProfile(sections: {
	person?: unknown;
	employments?: unknown;
	educations?: unknown;
	works?: unknown;
}): Partial<ORCIDProfile> {
	return {
		...(sections.person !== undefined ? parsePerson(sections.person) : {}),
		...(sections.employments !== undefined ? parseEmployments(sections.employments) : {}),
		...(sections.educations !== undefined ? parseEducations(sections.educations) : {}),
		...(sections.works !== undefined ? parseWorks(sections.works) : {})
	};
}
