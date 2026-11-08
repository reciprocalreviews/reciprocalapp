import { describe, expect, test } from 'vitest';
import {
	askable,
	consume,
	type Invitee,
	inviteeName,
	lookupable,
	offers,
	parseQueries,
	spokenFor,
	unanswered,
	unmatched
} from './inviteList';

const ORCID = '0000-0001-7461-1825';
const OTHER_ORCID = '0000-0002-1825-0097';
const amy: Invitee = { id: 'a', name: 'Amy Ko', orcid: ORCID };
const sam: Invitee = { id: 's', name: 'Sam Rivera', orcid: OTHER_ORCID };

/** Nothing asked about yet. */
const nothing = new Map<string, Invitee[]>();
const none = new Set<string>();

describe('parseQueries', () => {
	test('drops a trailing empty segment', () => {
		// A comma left behind while typing the next query is not a query that matches
		// nobody; it is nothing at all.
		expect(parseQueries(`${ORCID}, `)).toEqual([ORCID]);
	});

	test('trims and de-duplicates, preserving the order first given', () => {
		expect(parseQueries(' b@x.edu , a@x.edu, b@x.edu ')).toEqual(['b@x.edu', 'a@x.edu']);
	});

	test('reads an empty field as no queries', () => {
		expect(parseQueries('')).toEqual([]);
		expect(parseQueries('   ,  ')).toEqual([]);
	});
});

describe('lookupable', () => {
	test('accepts an email or an ORCID iD and nothing else', () => {
		expect(lookupable('amy@uw.edu')).toBe(true);
		expect(lookupable(ORCID)).toBe(true);
		expect(lookupable('Amy')).toBe(false);
	});

	test('a name is not lookupable but is still askable', () => {
		// The two are different questions now: lookupable routes to the address lookup,
		// askable decides whether to ask anything at all.
		expect(lookupable('Amy')).toBe(false);
		expect(askable('Amy')).toBe(true);
	});
});

describe('askable', () => {
	test('an address is askable however short', () => {
		expect(askable('a@b.co')).toBe(true);
	});

	test('two characters is enough of a name; one is not', () => {
		expect(askable('Am')).toBe(true);
		expect(askable('A')).toBe(false);
	});
});

describe('unanswered', () => {
	test('a query in the map is answered, even when it matched nobody', () => {
		const answers = new Map<string, Invitee[]>([['a@x.edu', []]]);
		expect(unanswered(['a@x.edu'], answers)).toEqual([]);
	});

	test('a query too short to search is never asked about', () => {
		expect(unanswered(['A'], nothing)).toEqual([]);
	});

	test('an askable query with no answer yet is what we are waiting on', () => {
		expect(unanswered([ORCID, 'Amy', 'A'], nothing)).toEqual([ORCID, 'Amy']);
	});
});

describe('offers', () => {
	test('follows the order the queries were typed, not the order they were answered', () => {
		const answers = new Map<string, Invitee[]>([
			['sam', [sam]],
			['amy', [amy]]
		]);
		expect(offers(['amy', 'sam'], answers, none).map((s) => s.id)).toEqual(['a', 's']);
	});

	test('a scholar matched by two queries is offered once', () => {
		// Pasting somebody's address and their ORCID iD names one person twice.
		const answers = new Map<string, Invitee[]>([
			[ORCID, [amy]],
			['amy@uw.edu', [amy]]
		]);
		expect(offers([ORCID, 'amy@uw.edu'], answers, none).map((s) => s.id)).toEqual(['a']);
	});

	test('somebody already accounted for is not offered', () => {
		const answers = new Map<string, Invitee[]>([['amy', [amy, sam]]]);
		expect(offers(['amy'], answers, new Set(['a'])).map((s) => s.id)).toEqual(['s']);
	});

	test('an unanswered query offers nobody', () => {
		expect(offers(['amy'], nothing, none)).toEqual([]);
	});
});

describe('unmatched', () => {
	test('a query answered with nobody is reported', () => {
		const answers = new Map<string, Invitee[]>([['nobody@x.edu', []]]);
		expect(unmatched(['nobody@x.edu'], answers)).toEqual(['nobody@x.edu']);
	});

	test('a query still being answered is not a failure', () => {
		expect(unmatched(['amy'], nothing)).toEqual([]);
	});

	test('a query whose matches were all excluded is not unmatched', () => {
		// That is spokenFor's news to deliver, and it reads differently.
		const answers = new Map<string, Invitee[]>([['amy', [amy]]]);
		expect(unmatched(['amy'], answers)).toEqual([]);
	});
});

describe('spokenFor', () => {
	test('every match already accounted for', () => {
		const answers = new Map<string, Invitee[]>([['amy', [amy]]]);
		expect(spokenFor(['amy'], answers, new Set(['a']))).toEqual(['amy']);
	});

	test('one free match is enough to not be spoken for', () => {
		const answers = new Map<string, Invitee[]>([['a', [amy, sam]]]);
		expect(spokenFor(['a'], answers, new Set(['a']))).toEqual([]);
	});

	test('a query matching nobody is not spoken for', () => {
		const answers = new Map<string, Invitee[]>([['nobody@x.edu', []]]);
		expect(spokenFor(['nobody@x.edu'], answers, none)).toEqual([]);
	});

	test('an unanswered query is not spoken for', () => {
		expect(spokenFor(['amy'], nothing, none)).toEqual([]);
	});
});

describe('consume', () => {
	test('removes the query that matched the chosen scholar', () => {
		const answers = new Map<string, Invitee[]>([
			['amy', [amy]],
			['sam', [sam]]
		]);
		expect(consume('amy, sam', 'a', answers)).toBe('sam');
	});

	test('removes BOTH queries when an address and an ORCID iD named the same person', () => {
		// The case the rule exists for: leaving the second behind leaves a query that can
		// no longer offer anybody.
		const answers = new Map<string, Invitee[]>([
			[ORCID, [amy]],
			['amy@uw.edu', [amy]]
		]);
		expect(consume(`${ORCID}, amy@uw.edu`, 'a', answers)).toBe('');
	});

	test('leaves a query that matched somebody else', () => {
		const answers = new Map<string, Invitee[]>([['a', [amy, sam]]]);
		expect(consume('a, other', 'x', answers)).toBe('a, other');
	});

	test('normalizes what is left on the way through', () => {
		const answers = new Map<string, Invitee[]>([['amy', [amy]]]);
		expect(consume('  amy ,  sam  , sam ', 'a', answers)).toBe('sam');
	});

	test('an empty field stays empty', () => {
		expect(consume('', 'a', nothing)).toBe('');
	});
});

describe('inviteeName', () => {
	test('prefers the name', () => {
		expect(inviteeName(amy)).toBe('Amy Ko');
	});

	test('falls back to the ORCID iD, then to the id, and is never empty', () => {
		expect(inviteeName({ id: 'x', name: null, orcid: ORCID })).toBe(ORCID);
		expect(inviteeName({ id: 'x', name: null, orcid: null })).toBe('x');
	});
});
