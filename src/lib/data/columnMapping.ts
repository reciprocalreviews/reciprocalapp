/** Mapping a CSV's own column names onto the fields the bulk importer needs.
 *
 * Every reviewing platform spells these columns differently, and there is no
 * list of platforms we could enumerate that would not go out of date. So the
 * importer does not recognize products: it parses whatever arrives, shows the
 * editor its real headers, and lets them say which column is which. What lives
 * here is only the *pre-selection* — a guess good enough that the common case is
 * confirming it rather than filling it in. Being wrong costs one dropdown. */

/** The fields a row of the importer is built from. Everything but `title` and
 * `externalID` may legitimately go unmapped. */
export type ImportField =
	'title' | 'externalID' | 'expertise' | 'submissionType' | 'previousID' | 'note';

/** Which CSV header feeds each field, or null when nothing does. */
export type ColumnMapping = Record<ImportField, string | null>;

/** Which CSV header names the holder of each venue role, keyed by role id. A
 * role with no entry reads no column.
 *
 * Deliberately not part of `ColumnMapping`: that is a total record over a fixed
 * set of fields, and a venue's roles are neither fixed nor knowable here. And
 * deliberately keyed by ROLE rather than by header — the form offers one menu
 * per role, so "each role is named by at most one column" is a property of the
 * type rather than a rule something has to check.
 *
 * Nothing guesses these. See the note on `guessMapping`. */
export type RoleColumns = Record<string, string>;

export const ImportFields: ImportField[] = [
	'title',
	'externalID',
	'expertise',
	'submissionType',
	'previousID',
	'note'
];

/** The fields a row cannot be imported without. */
export const RequiredFields: ImportField[] = ['title', 'externalID'];

/** A header split into lowercase alphanumeric words: "Manuscript ID" →
 * ['manuscript', 'id']. Separators, punctuation and case all stop mattering. */
export function normalizeHeader(header: string): string[] {
	return header
		.toLowerCase()
		.split(/[^a-z0-9]+/)
		.filter((token) => token.length > 0);
}

/** A header reduced to one comparable string: "External ID", "external_id" and
 * "externalid" all become 'externalid'. */
export function normalizeKey(header: string): string {
	return normalizeHeader(header).join('');
}

/** The importer's own column names, so a CSV already in its shape maps to itself
 * without going near the guesswork below. */
const Canonical: Record<ImportField, string[]> = {
	title: ['title'],
	externalID: ['externalid'],
	expertise: ['expertise'],
	submissionType: ['submissiontype'],
	previousID: ['previousid'],
	note: ['note']
};

/** Generic words that describe each concept — not column names from any
 * particular product. A header matches on the words it contains, so
 * "Manuscript ID", "Paper Number" and "Submission id" all reach `externalID`
 * without any of them being written down here. */
const Vocabulary: Record<ImportField, string[]> = {
	previousID: ['previous', 'original', 'parent', 'prior', 'resubmission'],
	title: ['title'],
	submissionType: ['type', 'category', 'track'],
	expertise: ['expertise', 'keyword', 'keywords', 'topic', 'topics', 'subject', 'area', 'areas'],
	note: ['note', 'notes', 'comment', 'comments', 'status'],
	externalID: ['id', 'number', 'no']
};

/** Words that mean "an identifier", needed by `previousID` on top of its own. */
const IdentifierWords = ['id', 'number', 'no'];

/** The order fields claim headers in: most specific first, so "Previous
 * Manuscript ID" is taken as a predecessor before the generic `id` rule can
 * claim it as the external ID. */
const ClaimOrder: ImportField[] = [
	'previousID',
	'title',
	'submissionType',
	'expertise',
	'note',
	'externalID'
];

/** How well one header fits one field: the share of the header's own words that
 * describe the concept. "Type" (1 of 1) beats "Manuscript Type" (1 of 2), which
 * is the difference between the column naming a thing and merely mentioning it.
 * Zero means no fit at all. */
function score(header: string, field: ImportField): number {
	const tokens = normalizeHeader(header);
	if (tokens.length === 0) return 0;

	const words = Vocabulary[field];
	const matches = tokens.filter((token) => words.includes(token)).length;
	if (matches === 0) return 0;

	// A predecessor column has to say both that it is previous and that it is an
	// identifier, or every "Original Title" would look like one.
	if (field === 'previousID' && !tokens.some((token) => IdentifierWords.includes(token))) return 0;

	return matches / tokens.length;
}

/** Guess which header feeds each field. Only a starting point: every field stays
 * editable, and a field whose best two candidates fit equally well is left
 * unmapped rather than decided by column order.
 *
 * Note what this deliberately does NOT guess: which column names the holder of a
 * venue role. For these fields a wrong guess costs a click and is visible — the
 * wrong text sits in the row table in front of the editor before they submit.
 * A wrong role guess costs an assignment: somebody seated on papers nobody gave
 * them, with a claim on the venue's tokens and, at the top role, the authority to
 * approve any assignment on the submission and mark it done — and it is invisible,
 * because a plausible name resolves to a real volunteer and the row looks correct.
 * Which of a file's columns corresponds to which of a venue's roles is venue
 * semantics, not vocabulary: an export naming an "Editor in Chief" and an "Editor"
 * may well mean the venue's top role and its associate editors respectively, and
 * matching on the role's own name would map them exactly the wrong way round.
 *
 * `fields` narrows which fields are guessed at all, so a caller that does not
 * offer a column does not claim a header for it either — otherwise that header
 * would vanish from the ignored-columns report while feeding nothing. */
export function guessMapping(
	headers: string[],
	fields: ImportField[] = ImportFields
): ColumnMapping {
	const mapping: ColumnMapping = {
		title: null,
		externalID: null,
		expertise: null,
		submissionType: null,
		previousID: null,
		note: null
	};

	const claimed = new Set<string>();
	const wanted = ClaimOrder.filter((field) => fields.includes(field));

	// An exact match on the importer's own column name is not a guess, so it is
	// settled first and never loses to the scoring below.
	for (const field of wanted) {
		const exact = headers.filter(
			(header) => !claimed.has(header) && Canonical[field].includes(normalizeKey(header))
		);
		if (exact.length === 1) {
			mapping[field] = exact[0];
			claimed.add(exact[0]);
		}
	}

	for (const field of wanted) {
		if (mapping[field] !== null) continue;

		let best: string | null = null;
		let bestScore = 0;
		let tied = false;
		for (const header of headers) {
			if (claimed.has(header)) continue;
			const fit = score(header, field);
			if (fit === 0) continue;
			if (fit > bestScore) {
				best = header;
				bestScore = fit;
				tied = false;
			} else if (fit === bestScore) {
				tied = true;
			}
		}

		// Two columns that fit equally well is a question for the editor, not
		// something to settle by whichever came first in the file.
		if (best !== null && !tied) {
			mapping[field] = best;
			claimed.add(best);
		}
	}

	return mapping;
}

/** The headers nothing is reading, so the importer can say so rather than drop
 * them in silence.
 *
 * `roleColumns` is required rather than defaulted: a caller who forgot it would
 * report every column feeding a role as ignored, and this report exists precisely
 * so an editor can trust that nothing was silently dropped. */
export function unmappedHeaders(
	headers: string[],
	mapping: ColumnMapping,
	roleColumns: RoleColumns
): string[] {
	const used = new Set([
		...Object.values(mapping).filter((header): header is string => header !== null),
		...Object.values(roleColumns)
	]);
	return headers.filter((header) => !used.has(header));
}
