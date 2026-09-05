/** Resolving a name written in a CSV to a scholar the venue already knows.
 *
 * A bulk import may name the person to seat on each submission, and exports
 * write names however their platform does — "Petersen, Andrew" one place,
 * "Andrew Petersen" another. Matching them is therefore necessary, but it is
 * also a decision with consequences: a seated assignment carries authority over
 * the submission and a claim on the venue's tokens. So the rules here are
 * deliberately narrow.
 *
 * Two things keep it safe. Candidates come from a closed list — the venue's own
 * accepted, active volunteers in the chosen role — never a search across every
 * scholar on the platform. And anything short of a single confident match is
 * reported rather than guessed: an ambiguous name is handed back with its
 * candidates for a person to choose between, and an unmatched one blocks the
 * import. There is no fuzzy or substring matching, because the cost of being
 * subtly wrong is much higher than the cost of one more click. */

/** A scholar the name could refer to. */
export type Candidate = { id: string; name: string };

export type PersonMatch =
	/** The cell is empty; the row names nobody. */
	| { status: 'none' }
	| { status: 'resolved'; id: string }
	/** Several candidates fit equally well; a person must choose. */
	| { status: 'ambiguous'; candidates: Candidate[] }
	/** Nobody in the candidate list matches. */
	| { status: 'unmatched' };

/** A name reduced to comparable words: lowercased, stripped of accents and of
 * the punctuation that separates a surname from a given name, so
 * "Petersen, Andrew" and "Andrew Petersen" become the same set of words.
 *
 * Accents are removed rather than compared because an export and a profile
 * often disagree about them, and "Munoz" failing to match "Muñoz" would be a
 * false mismatch rather than a useful distinction. */
export function nameTokens(name: string): string[] {
	return name
		.normalize('NFD')
		.replace(/[\u0300-\u036f]/g, '')
		.toLowerCase()
		.split(/[^a-z0-9]+/)
		.filter((token) => token.length > 0);
}

/** Whether two names use exactly the same words, in any order. */
function sameWords(a: string[], b: string[]): boolean {
	if (a.length !== b.length) return false;
	const sorted = [...a].sort();
	const other = [...b].sort();
	return sorted.every((token, i) => token === other[i]);
}

/** Whether two names agree once initials are taken into account — which is what
 * separates "Petersen, Andrew J." from "Andrew Petersen" without letting a bare
 * surname match anybody who shares it.
 *
 * Every word of the shorter name must pair with a distinct word of the longer,
 * either identically or as an initial against the word it abbreviates. At least
 * one pairing must be a whole word, so agreeing only on initials is not enough,
 * and anything left over in the longer name must itself be an initial — so
 * "Petersen" alone does not match "Andrew Petersen", which is a different
 * person's name with a word missing. */
function initialsAgree(a: string[], b: string[]): boolean {
	if (a.length === 0 || b.length === 0) return false;

	const [short, long] = a.length <= b.length ? [a, b] : [b, a];
	const paired = new Array(long.length).fill(false);
	let wholeWords = 0;

	for (const word of short) {
		// Prefer a whole-word pairing, so an initial does not consume a word that
		// something else needed.
		let found = long.findIndex((other, i) => !paired[i] && other === word);
		if (found >= 0) wholeWords++;
		else
			found = long.findIndex(
				(other, i) =>
					!paired[i] && (word.length === 1 || other.length === 1) && other[0] === word[0]
			);
		if (found < 0) return false;
		paired[found] = true;
	}

	if (wholeWords === 0) return false;

	// A word of the longer name that nothing accounts for means these are two
	// different names, unless it is just an initial.
	return long.every((word, i) => paired[i] || word.length === 1);
}

/** Resolve a written name against the venue's candidates.
 *
 * Exact word-for-word agreement is tried first, then agreement allowing for
 * initials. Either step resolves only when exactly one candidate qualifies;
 * anything else is reported as ambiguous or unmatched. */
export function matchPersonName(name: string, candidates: Candidate[]): PersonMatch {
	const written = nameTokens(name);
	if (written.length === 0) return { status: 'none' };

	const exact = candidates.filter((c) => sameWords(written, nameTokens(c.name)));
	if (exact.length === 1) return { status: 'resolved', id: exact[0].id };
	if (exact.length > 1) return { status: 'ambiguous', candidates: exact };

	const loose = candidates.filter((c) => initialsAgree(written, nameTokens(c.name)));
	if (loose.length === 1) return { status: 'resolved', id: loose[0].id };
	if (loose.length > 1) return { status: 'ambiguous', candidates: loose };

	return { status: 'unmatched' };
}
