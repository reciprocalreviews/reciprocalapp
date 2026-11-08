/**
 * What a comma-separated invite field's queries currently match, and who has been chosen
 * to invite.
 *
 * The field takes a list of email addresses, ORCID iDs, and names, in any mix, and offers
 * the scholars each query matches; clicking one moves that scholar to the list to be
 * invited and takes the query that found them out of the field. The rules for reading
 * that list live here rather than in the component, because they are rules — which
 * queries are worth asking about, which have been answered, who is still on offer, which
 * queries turned up nobody, which query a chosen scholar came from — and a component is a
 * poor place to check them.
 *
 * Nothing here depends on the database layer. `Invitee` is written out rather than
 * imported because both queries the component makes already return exactly that shape:
 * `ScholarMatch` (a name search) and `ScholarInvitee` (an address lookup) are structurally
 * identical, which is the whole reason one cache can hold the answers to both and one row
 * can offer them side by side.
 */

import { validEmail, validORCID } from '../validation';
import { parseAddresses } from './addresses';

/** A scholar a query matched: enough to name them on a button and to invite them. */
export type Invitee = { id: string; name: string | null; orcid: string | null };

/** The answers so far, keyed by the exact query text that was asked.
 *
 * Keyed by TEXT and not by position, and that is what makes a field of several queries
 * simple. Editing the first query leaves the second one's answer where it is, and an
 * answer that lands late lands under the question it was about — so there is no per-query
 * sequence number here and none in the component either, unlike ScholarSearch, which asks
 * one question over and over and really can have a slow earlier answer overwrite a later
 * one.
 *
 * An absent key has not been asked about; an empty array means asked and matched nobody.
 * The difference is the point: one reads as silence, the other has something to say.
 * Queries typed on the way to another one ("An" before "Anne") stay in the map and do no
 * harm, since nothing reads a key that is no longer a query. */
export type Answers = ReadonlyMap<string, Invitee[]>;

/** The shortest name fragment worth searching for. Deliberately a second copy of
 * ScholarSearch's own constant rather than a shared one: a change to how one field decides
 * somebody is mid-keystroke is not automatically a change to the other. */
export const MIN_NAME_QUERY = 2;

/** The queries the field currently holds: trimmed, de-duplicated, empties dropped.
 *
 * parseAddresses is identifier-agnostic despite its email-centric doc comment. Dropping
 * empties is what makes a trailing comma a non-event rather than a query that matches
 * nobody, and de-duplicating is what stops one query being asked twice in a batch. */
export function parseQueries(text: string): string[] {
	return parseAddresses(text);
}

/** Whether a query names somebody exactly, and so is answered by an address lookup rather
 * than a name search.
 *
 * No longer a validity rule. The field takes names now, so there is nothing it can hold
 * that is a mistake — this decides only which question to ask about it. */
export function lookupable(query: string): boolean {
	return validEmail(query) || validORCID(query);
}

/** Whether a query is worth asking about at all.
 *
 * A single letter is somebody mid-keystroke, and searching for it would offer a third of
 * the platform. It reads as silence on screen, which is what it is: the field saying
 * exactly what it was asked to say at that moment. Addresses are exempt from the length
 * floor because they are already exact. */
export function askable(query: string): boolean {
	return lookupable(query) || query.length >= MIN_NAME_QUERY;
}

/** The queries that should be asked about now: askable, and not yet answered.
 *
 * Also what "still searching" means on screen. A query about to be asked and one asked and
 * awaiting an answer both mean an answer is coming, and there is nothing worth telling the
 * reader that would distinguish them. */
export function unanswered(queries: string[], answers: Answers): string[] {
	return queries.filter((query) => askable(query) && !answers.has(query));
}

/** Who the field is offering: every scholar the answered queries matched, in the order the
 * queries were typed, each of them once, minus anyone already accounted for.
 *
 * `accounted` is the scholars already on this role's volunteer list together with the ones
 * already chosen. Both are excluded for one reason: create_volunteer refuses a second row
 * for a (scholar, role) pair whatever state the first one is in — invited, accepted,
 * declined, paused — so offering them would be offering something that cannot happen. */
export function offers(
	queries: string[],
	answers: Answers,
	accounted: ReadonlySet<string>
): Invitee[] {
	const seen = new Set<string>();
	const offered: Invitee[] = [];
	for (const query of queries)
		for (const scholar of answers.get(query) ?? []) {
			if (seen.has(scholar.id) || accounted.has(scholar.id)) continue;
			seen.add(scholar.id);
			offered.push(scholar);
		}
	return offered;
}

/** The queries that were asked and matched nobody at all.
 *
 * Named on screen rather than left silent, and deliberately NOT a reason to refuse the
 * invitation. The list used to be all or nothing, so one mistyped address held the other
 * four people hostage; an admin who cannot find one person should be able to invite the
 * rest and come back for them. */
export function unmatched(queries: string[], answers: Answers): string[] {
	return queries.filter((query) => answers.get(query)?.length === 0);
}

/** The queries whose every match is somebody already accounted for.
 *
 * Reported apart from `unmatched`, because "nobody here is called that" and "they are
 * already on the list" are different news — and the second is the common one, since an
 * admin working down a roster will name people they have already added. Without it such a
 * query offers nothing and says nothing, which reads as the field having failed rather
 * than as it having answered. */
export function spokenFor(
	queries: string[],
	answers: Answers,
	accounted: ReadonlySet<string>
): string[] {
	return queries.filter((query) => {
		const matches = answers.get(query);
		return matches !== undefined && matches.length > 0 && matches.every((m) => accounted.has(m.id));
	});
}

/** The field with every query that matched this scholar taken out.
 *
 * Every query, not just the first one. An admin who pasted somebody's address AND their
 * ORCID iD named one person twice, and leaving the second query behind would leave one
 * that can no longer offer anybody — the person it names has just been chosen — and so has
 * nothing left to say for itself. The cost is that a broader query goes with a narrower
 * one: choosing Ann Thesis from "Ann, Ann Thesis" also takes "Ann", and with it Anne
 * Notation's offer. That is a retype, which is cheaper than residue nobody can act on.
 *
 * Rejoining through parseQueries also normalizes what is left — trimmed, de-duplicated —
 * so the field settles into a canonical form as it is worked through. */
export function consume(text: string, scholar: string, answers: Answers): string {
	return parseQueries(text)
		.filter((query) => !(answers.get(query) ?? []).some((match) => match.id === scholar))
		.join(', ');
}

/** What to call a scholar on a button.
 *
 * A scholar found by their verified address may have neither a name nor an ORCID iD — the
 * name search excludes both, the address lookup cannot — and a button labelled with an
 * empty string cannot be read, clicked with any confidence, or announced. An id is a poor
 * name, but it is never nothing. ScholarMatches settles for `?? ''` here, which is the bug
 * this avoids. */
export function inviteeName(scholar: Invitee): string {
	return scholar.name ?? scholar.orcid ?? scholar.id;
}
