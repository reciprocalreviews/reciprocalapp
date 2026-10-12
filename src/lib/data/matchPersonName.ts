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
 * subtly wrong is much higher than the cost of one more click.
 *
 * suggestCandidates and searchCandidates, below, ARE fuzzy, and that is fine for the
 * same reason: they only order and filter what a person chooses from, and the choice
 * stays theirs. */

import type { VenueCommitment } from './SupabaseCRUD.svelte';
import { affiliationLine } from './orcidProfileView';

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

/** A candidate with what a person needs to tell them apart from someone who shares their
 * name: how to reach them, their ORCID iD, and where they work. */
export type Volunteer = Candidate & {
	email: string | null;
	orcid: string | null;
	affiliation: string | null;
};

/** How far a written name may be from a volunteer's, in single-letter edits, for the
 * volunteer to be suggested. Two catches a dropped, doubled or swapped letter, which
 * is what export typos look like, without suggesting everyone who merely shares a
 * surname: a list of near strangers is worse than no list, because it invites a
 * plausible wrong click. */
const SUGGESTION_DISTANCE = 2;

/** The number of single-letter insertions, deletions and substitutions between two words. */
function editDistance(a: string, b: string): number {
	let previous = Array.from({ length: b.length + 1 }, (_, i) => i);
	for (let i = 1; i <= a.length; i++) {
		const current = [i];
		for (let j = 1; j <= b.length; j++)
			current[j] = Math.min(
				previous[j] + 1,
				current[j - 1] + 1,
				previous[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1)
			);
		previous = current;
	}
	return previous[b.length];
}

/** What it costs to turn one word into another: nothing for an initial that agrees
 * with the word it abbreviates, otherwise the edit distance. */
function wordDistance(a: string, b: string): number {
	if ((a.length === 1 || b.length === 1) && a[0] === b[0]) return 0;
	return editDistance(a, b);
}

/** How many single-letter edits separate two names, in any word order. Each word of
 * the written name pairs with the closest unpaired word of the candidate's, longest
 * words first so an initial cannot take a word a whole name needed. A word left over
 * on either side costs its length, unless it is only an initial, since "Andrew J.
 * Petersen" and "Andrew Petersen" are the same person. Infinite when no whole word
 * pairs, so initials alone never suggest anyone. */
function nameDistance(written: string[], candidate: string[]): number {
	const paired = new Array(candidate.length).fill(false);
	let total = 0;
	let whole = false;
	for (const word of [...written].sort((a, b) => b.length - a.length)) {
		let best = -1;
		let bestDistance = Infinity;
		candidate.forEach((other, i) => {
			if (paired[i]) return;
			const distance = wordDistance(word, other);
			if (distance < bestDistance) {
				best = i;
				bestDistance = distance;
			}
		});
		if (best < 0 || bestDistance >= word.length) {
			total += word.length === 1 ? 0 : word.length;
			continue;
		}
		paired[best] = true;
		total += bestDistance;
		whole ||= word.length > 1 && candidate[best].length > 1;
	}
	candidate.forEach((word, i) => {
		if (!paired[i] && word.length > 1) total += word.length;
	});
	return whole ? total : Infinity;
}

/** The candidates whose names are within a couple of typos of a written one, closest
 * first, for a person to choose between. Often none: a name that is not nearly
 * somebody's suggests nobody.
 *
 * Unlike matchPersonName this tolerates typos, and that is safe only because it
 * decides nothing: it offers, and the person picks. Ties are broken by name, so the
 * same list always comes back in the same order. */
export function suggestCandidates<C extends Candidate>(
	name: string,
	candidates: C[],
	limit = 3
): C[] {
	const written = nameTokens(name);
	if (written.length === 0) return [];
	return candidates
		.map((candidate) => ({
			candidate,
			distance: nameDistance(written, nameTokens(candidate.name))
		}))
		.filter(({ distance }) => distance <= SUGGESTION_DISTANCE)
		.sort((a, b) => a.distance - b.distance || a.candidate.name.localeCompare(b.candidate.name))
		.slice(0, limit)
		.map(({ candidate }) => candidate);
}

/** The volunteers a search could mean, sorted by name. Every word typed must begin a
 * word of the name or appear in the email address or ORCID iD, so "pet" finds both
 * Petersens and "0000-0002" finds an iD. Accents and case are ignored, as they are for
 * matching. */
export function searchCandidates<C extends Volunteer>(query: string, candidates: C[]): C[] {
	const words = nameTokens(query);
	if (words.length === 0) return [];
	return candidates
		.filter((candidate) => {
			const name = nameTokens(candidate.name);
			const email = candidate.email?.toLowerCase() ?? '';
			const orcid = candidate.orcid ?? '';
			return words.every(
				(word) =>
					name.some((part) => part.startsWith(word)) || email.includes(word) || orcid.includes(word)
			);
		})
		.sort((a, b) => a.name.localeCompare(b.name) || (a.email ?? '').localeCompare(b.email ?? ''));
}

/** A role's accepted, active volunteers, the only people the database will seat in it,
 * with what tells them apart. Scholars with no name are left out, since there is
 * nothing to match a written name against. */
export function volunteersFor(commitments: VenueCommitment[], role: string): Volunteer[] {
	return commitments
		.filter((c) => c.roleid === role && c.active && c.accepted === 'accepted')
		.map((c) => ({
			id: c.scholarid,
			name: c.scholars?.name ?? '',
			email: c.scholars?.email ?? null,
			orcid: c.scholars?.orcid ?? null,
			affiliation: affiliationLine(c.scholars?.orcid_profiles, true)
		}))
		.filter((c) => c.name.length > 0);
}
