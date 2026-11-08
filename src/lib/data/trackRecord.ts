import type { ORCIDWorkJournal } from './orcidProfile';

/**
 * Evidence that a volunteer fits a venue, for ranking the volunteers roster for those who
 * scout it. Three facts, none of them a judgment anyone recorded about the person: roles
 * they hold or have held at the venue that nobody can give themselves, reviews they have
 * finished there, and works their ORCID record places in one of its relevant venues.
 *
 * The matching rules here are the only ones: the roster ranks with them and the settings
 * preview shows them, so what an editor sees while typing is what the roster will do.
 */
export type TrackRecord = {
	/** Vetted roles held at this venue, current first. See `venueRoles`. */
	roles: VenueRole[];
	/** Whether they are one of the venue's admins. */
	admin: boolean;
	/** Approved, completed assignments at this venue, in any role. */
	completed: number;
	/** Works in the venue's relevant venues, per the scholar's public ORCID record. */
	venueWorks: number;
	/** The journal titles those works were matched on, so a reader can catch a false match. */
	venueJournals: ORCIDWorkJournal[];
};

/** A role someone holds, or once held, at the venue. */
export type VenueRole = { role: string; name: string; current: boolean };

/** 0 holds or held a vetted role, or reviewed here; 1 published in a relevant venue;
 * 2 none of these. Lower sorts first. */
export type TrackTier = 0 | 1 | 2;

/** Words a venue's name is written with or without, so neither side needs them:
 * "Proceedings of the ACM ..." and "... (ACM)" are the same venue as the bare name. */
const FILLER = new Set([
	'proceedings',
	'proc',
	'of',
	'the',
	'on',
	'for',
	'and',
	'in',
	'a',
	'an',
	'at',
	'acm',
	'ieee',
	'annual',
	'vol',
	'v',
	'part'
]);

/** The words of a title or name that identify a venue. Lowercased, accents and
 * punctuation removed, letters split from digits ("ICER2023" is "icer 2023"), and then
 * filler words, ordinals ("55th") and numbers (years, volumes) dropped. */
export function venueWords(text: string): string[] {
	return text
		.normalize('NFKD')
		.replace(/\p{M}/gu, '')
		.toLowerCase()
		.replace(/\d+(st|nd|rd|th)\b/g, ' ')
		.replace(/[^\p{L}\p{N}]+/gu, ' ')
		.replace(/(\p{L})(\p{N})/gu, '$1 $2')
		.replace(/(\p{N})(\p{L})/gu, '$1 $2')
		.split(' ')
		.filter((word) => word.length > 0 && !FILLER.has(word) && !/^\p{N}+$/u.test(word));
}

/** One line of the setting: the names a single venue goes by, separated by commas. */
export function venueNames(line: string): string[] {
	return line
		.split(',')
		.map((name) => name.trim().replace(/\s+/g, ' '))
		.filter((name) => venueWords(name).length > 0);
}

/** Parse the settings field into the stored form: one venue per line, blank lines and
 * lines naming nothing dropped, each line's names tidied. */
export function parseRelevantVenues(text: string): string[] {
	const seen = new Set<string>();
	return text
		.split('\n')
		.map((line) => venueNames(line).join(', '))
		.filter((line) => {
			const key = venueWords(line).join(' ');
			if (key.length === 0 || seen.has(key)) return false;
			seen.add(key);
			return true;
		});
}

/** Whether two words are the same word, or one abbreviates the other: "trans" for
 * "transactions", "comput" for "computing". Three letters at least, so "a" or "co"
 * abbreviate nothing. */
function sameWord(a: string, b: string): boolean {
	if (a === b) return true;
	const [short, long] = a.length < b.length ? [a, b] : [b, a];
	return short.length >= 3 && long.startsWith(short);
}

/** Whether a name's words occur in a title's words, together and in order. A one-word
 * name, which is usually an acronym, must be a whole word of the title, never a prefix:
 * "ICER" is not "ICERI". */
function nameMatches(title: string[], name: string[]): boolean {
	if (name.length === 0 || name.length > title.length) return false;
	const same = name.length === 1 ? (a: string, b: string) => a === b : sameWord;
	for (let start = 0; start + name.length <= title.length; start++)
		if (name.every((word, i) => same(title[start + i], word))) return true;
	return false;
}

/** A matcher for one line of the setting: true when any of the venue's names matches. */
function lineMatcher(line: string): (titleWords: string[]) => boolean {
	const names = venueNames(line).map(venueWords);
	return (titleWords) => names.some((name) => nameMatches(titleWords, name));
}

/** Whether a journal or proceedings title is one of the relevant venues. */
export function matchesRelevantVenue(journal: string, lines: string[]): boolean {
	const title = venueWords(journal);
	return lines.some((line) => lineMatcher(line)(title));
}

/** The journals in a record that are relevant venues. */
export function venueJournals(journals: ORCIDWorkJournal[], lines: string[]): ORCIDWorkJournal[] {
	const matchers = lines.map(lineMatcher);
	if (matchers.length === 0) return [];
	return journals.filter((j) => {
		const title = venueWords(j.journal);
		return matchers.some((matches) => matches(title));
	});
}

/**
 * The roles a scholar holds, or has held, at the venue that count as a track record: an
 * accepted record, active or not, in an invite-only role or the venue's top role. Those
 * are the roles nobody can award themselves, the same two the roster lists whatever a
 * venue's visibility setting, which is also why every viewer's roster holds all of them.
 * An open role does not count, or volunteering twice would earn a track record. Current
 * roles come first, then former ones, each in priority order.
 */
export function venueRoles(
	scholar: string,
	records: { scholarid: string; roleid: string; accepted: string; active: boolean }[],
	roles: { id: string; name: string; priority: number; invited: boolean }[]
): VenueRole[] {
	const vetted = new Map(roles.filter((r) => r.invited || r.priority === 0).map((r) => [r.id, r]));
	return records
		.filter((v) => v.scholarid === scholar && v.accepted === 'accepted' && vetted.has(v.roleid))
		.flatMap((v) => {
			const role = vetted.get(v.roleid);
			return role === undefined
				? []
				: [{ role: role.id, name: role.name, current: v.active, priority: role.priority }];
		})
		.sort((a, b) => Number(b.current) - Number(a.current) || a.priority - b.priority)
		.map(({ role, name, current }) => ({ role, name, current }));
}

export function trackRecord(
	completed: number,
	journals: ORCIDWorkJournal[],
	lines: string[],
	standing: { roles: VenueRole[]; admin: boolean } = { roles: [], admin: false }
): TrackRecord {
	const matched = venueJournals(journals, lines);
	return {
		roles: standing.roles,
		admin: standing.admin,
		completed,
		venueWorks: matched.reduce((sum, j) => sum + j.count, 0),
		venueJournals: matched
	};
}

export function trackTier(record: TrackRecord): TrackTier {
	if (record.completed > 0 || record.roles.length > 0 || record.admin) return 0;
	if (record.venueWorks > 0) return 1;
	return 2;
}

export type RelevantVenuePreview = {
	line: string;
	/** How many of the given scholars have a work this line matches. */
	scholars: number;
	/** Distinct journal titles it matched, most common first, at most `limit`. */
	titles: string[];
};

/** What each line of the setting matches among a venue's volunteers, for the settings
 * page to show while an editor writes it. */
export function previewRelevantVenues(
	lines: string[],
	records: { scholar: string; journals: ORCIDWorkJournal[] }[],
	limit = 3
): RelevantVenuePreview[] {
	return lines.map((line) => {
		const matches = lineMatcher(line);
		const scholars = new Set<string>();
		const titles = new Map<string, number>();
		for (const { scholar, journals } of records)
			for (const j of journals)
				if (matches(venueWords(j.journal))) {
					scholars.add(scholar);
					titles.set(j.journal, (titles.get(j.journal) ?? 0) + j.count);
				}
		return {
			line,
			scholars: scholars.size,
			titles: [...titles.entries()]
				.sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
				.slice(0, limit)
				.map(([title]) => title)
		};
	});
}

/** Read `orcid_profiles.work_journals`, which arrives as untyped jsonb, keeping only
 * well-formed entries: a malformed row loses its journals rather than breaking the roster. */
export function workJournals(value: unknown): ORCIDWorkJournal[] {
	if (!Array.isArray(value)) return [];
	return value.flatMap((entry: unknown) =>
		typeof entry === 'object' &&
		entry !== null &&
		'journal' in entry &&
		'count' in entry &&
		typeof entry.journal === 'string' &&
		typeof entry.count === 'number'
			? [{ journal: entry.journal, count: entry.count }]
			: []
	);
}
