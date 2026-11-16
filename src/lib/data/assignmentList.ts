/** Assigning from a list: a manuscript ID and who, one per line, pasted from the
 * spreadsheet a venue's reviewing system exports or the one an editor keeps beside it.
 *
 * The bulk importer already seats named people on the rows it creates, but skips a
 * manuscript the venue has, and submissions paid for here are exactly those. So an editor
 * who has just made a round of assignments in the reviewing system would otherwise make
 * every one again by hand. This reads the same list and resolves each person the way the
 * importer does: against the role's own volunteers, never everyone on the platform. */

import type {
	AssignFromListResult,
	ListAssignment,
	ListAssignmentRow,
	ListAssignmentVerdict
} from './CRUD';
import { matchPersonName, nameTokens, type PersonMatch, type Volunteer } from './matchPersonName';

/** One non-blank line of the list, as written. */
export type ListLine = {
	/** The manuscript ID, trimmed, as every stored ID is. */
	externalID: string;
	/** The name or email address, trimmed. Empty when the line had only an ID. */
	written: string;
};

/** Whether a cell holds a number, which is what tells a manuscript ID from a name. */
function hasDigit(cell: string): boolean {
	return /\d/.test(cell);
}

/** The cells of one line: tab-separated (a spreadsheet's columns) if it has a tab, else
 * comma- or semicolon-separated, else space-separated -- but only when exactly one word
 * carries a number, since some reviewing systems put spaces inside their IDs and a line
 * like that is one whole ID. Returns the separator used, which decides how leftover cells
 * become the name. */
function cellsOf(raw: string): { cells: string[]; separator: 'tab' | 'comma' | 'space' | 'none' } {
	if (raw.includes('\t')) return { cells: raw.split('\t'), separator: 'tab' };
	if (/[,;]/.test(raw)) return { cells: raw.split(/[,;]/), separator: 'comma' };
	const words = raw.trim().split(/\s+/);
	if (words.length > 1 && words.filter((w) => hasDigit(w) && !looksLikeEmail(w)).length === 1)
		return { cells: words, separator: 'space' };
	return { cells: [raw], separator: 'none' };
}

/** The lines in pasted text: a manuscript ID and a name or email, in either order.
 *
 * The ID is the first cell holding a number that is not an email address -- manuscript
 * IDs carry numbers, and names do not -- so a list copied with its columns the other way
 * round reads the same. A line where no cell qualifies (a header row, say) keeps the old
 * reading, ID first. The rest is the person: with tabs, the first other non-empty cell,
 * so further spreadsheet columns are ignored; otherwise every other cell joined back
 * together, so "Petersen, Andrew, TOK-0142" keeps its "Surname, Given". Blank lines are
 * dropped. */
export function parseAssignmentList(text: string): ListLine[] {
	const lines: ListLine[] = [];
	for (const raw of text.split(/\r\n|\r|\n/)) {
		if (raw.trim() === '') continue;
		const { cells, separator } = cellsOf(raw);
		const trimmed = cells.map((cell) => cell.trim());
		const found = trimmed.findIndex((cell) => hasDigit(cell) && !looksLikeEmail(cell));
		const at = found < 0 ? 0 : found;
		const others = trimmed.filter((cell, index) => index !== at && cell !== '');
		const written =
			separator === 'tab' ? (others[0] ?? '') : others.join(separator === 'comma' ? ', ' : ' ');
		lines.push({ externalID: trimmed[at], written });
	}
	return lines;
}

/** Whether a cell is an email address rather than a name. Loose on purpose: it only
 * decides which of the volunteers' fields the cell is compared with. */
export function looksLikeEmail(written: string): boolean {
	return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(written);
}

/** Who a cell means among the role's volunteers. An email address resolves only to the
 * volunteer whose address it is, ignoring case; a name resolves as the importer resolves
 * one, or, failing that, by a first or last name alone that just one of them has. A
 * choice the editor pinned wins while it is still one of the candidates. */
export function resolveWho(
	written: string,
	candidates: Volunteer[],
	pinned: string | undefined = undefined
): PersonMatch {
	if (pinned !== undefined && candidates.some((c) => c.id === pinned))
		return { status: 'resolved', id: pinned };
	if (written === '') return { status: 'none' };
	if (looksLikeEmail(written)) {
		const address = written.toLowerCase();
		const found = candidates.filter((c) => c.email?.toLowerCase() === address);
		return found.length === 1 ? { status: 'resolved', id: found[0].id } : { status: 'unmatched' };
	}
	const match = matchPersonName(written, candidates);
	if (match.status !== 'unmatched') return match;

	// A first or last name alone. The importer refuses this, so that "Petersen" never
	// seats some other Petersen; here the person who pasted the list sees each line's full
	// name before anything is written, and a name two volunteers share still asks them to
	// choose, so one word is enough to go on.
	const words = nameTokens(written);
	if (words.length !== 1) return match;
	const sharing = candidates.filter((c) => nameTokens(c.name).includes(words[0]));
	if (sharing.length === 1) return { status: 'resolved', id: sharing[0].id };
	if (sharing.length > 1) return { status: 'ambiguous', candidates: sharing };
	return match;
}

/** Manuscript IDs the list names more than once, by the index of every line after the
 * first that names it. Those lines block the list, as a manuscript an import file names
 * twice does: the two lines may name different people, and choosing would discard one. */
export function repeatedLines(lines: ListLine[]): Set<number> {
	const seen = new Set<string>();
	const repeated = new Set<number>();
	lines.forEach((line, index) => {
		if (line.externalID === '') return;
		if (seen.has(line.externalID)) repeated.add(index);
		seen.add(line.externalID);
	});
	return repeated;
}

/** What the form sends for a line: the resolved scholar, or the written name when it
 * matched nobody, which is kept as an unmatched assignment for an approver to match once
 * the person joins. An email address that matched nobody is not a name anyone could match
 * later, so it sends nothing; nor does an ambiguous name, which must be chosen first, or a
 * line with no ID or nobody. */
export function toListAssignment(line: ListLine, match: PersonMatch): ListAssignment | null {
	if (line.externalID === '') return null;
	if (match.status === 'resolved') return { externalid: line.externalID, person: match.id };
	if (match.status === 'unmatched' && !looksLikeEmail(line.written))
		return { externalid: line.externalID, name: line.written };
	return null;
}

/** Verdicts that mean the line will do something when confirmed. */
export const ActionableVerdicts: ReadonlySet<ListAssignmentVerdict> = new Set(['ready', 'keep']);

/** Verdicts that are a reason to look again before confirming, as opposed to harmless
 * no-ops like a seat the person already holds. */
export const ProblemVerdicts: ReadonlySet<ListAssignmentVerdict> = new Set([
	'missing',
	'duplicate',
	'done',
	'recused',
	'not_volunteer',
	'author',
	'conflicted',
	'held',
	'waiting'
]);

const Verdicts: ReadonlySet<string> = new Set<ListAssignmentVerdict>([
	'missing',
	'duplicate',
	'done',
	'recused',
	'not_volunteer',
	'author',
	'conflicted',
	'already',
	'held',
	'waiting',
	'ready',
	'keep',
	'seated',
	'kept'
]);

function isVerdict(value: unknown): value is ListAssignmentVerdict {
	return typeof value === 'string' && Verdicts.has(value);
}

function stringOrNull(value: unknown): string | null | undefined {
	return value === null ? null : typeof value === 'string' ? value : undefined;
}

function parseRow(value: unknown): ListAssignmentRow | null {
	if (typeof value !== 'object' || value === null) return null;
	if (!('externalid' in value) || typeof value.externalid !== 'string') return null;
	if (!('verdict' in value) || !isVerdict(value.verdict)) return null;
	const submission = 'submission' in value ? stringOrNull(value.submission) : null;
	const title = 'title' in value ? stringOrNull(value.title) : null;
	const holder = 'holder' in value ? stringOrNull(value.holder) : null;
	if (submission === undefined || title === undefined || holder === undefined) return null;
	return { externalid: value.externalid, verdict: value.verdict, submission, title, holder };
}

/** Read what public.assign_submissions returned, or null when it is not that shape. */
export function parseAssignFromListResult(value: unknown): AssignFromListResult | null {
	if (typeof value !== 'object' || value === null) return null;
	if (!('rows' in value) || !Array.isArray(value.rows)) return null;
	const rows: ListAssignmentRow[] = [];
	for (const raw of value.rows) {
		const row = parseRow(raw);
		if (row === null) return null;
		rows.push(row);
	}
	const count = (key: 'seated' | 'kept' | 'skipped') => {
		const field: unknown = key in value ? Reflect.get(value, key) : undefined;
		return typeof field === 'number' ? field : null;
	};
	const seated = count('seated');
	const kept = count('kept');
	const skipped = count('skipped');
	if (seated === null || kept === null || skipped === null) return null;

	const seatedBy: Record<string, number> = {};
	const by: unknown = 'seated_by' in value ? value.seated_by : {};
	if (typeof by !== 'object' || by === null) return null;
	for (const [scholar, n] of Object.entries(by)) {
		if (typeof n !== 'number') return null;
		seatedBy[scholar] = n;
	}
	return { rows, seated, seatedBy, kept, skipped };
}
