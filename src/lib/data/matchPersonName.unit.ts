import { describe, expect, test } from 'vitest';
import {
	matchPersonName,
	nameTokens,
	searchCandidates,
	suggestCandidates,
	type Candidate,
	type Volunteer
} from './matchPersonName';

const PETERSEN: Candidate = { id: 'p', name: 'Andrew Petersen' };
const SOH: Candidate = { id: 's', name: 'Leen-Kiat Soh' };
const MUNOZ: Candidate = { id: 'm', name: 'Ana Muñoz' };

describe('nameTokens', () => {
	test('reduces either name order to the same words', () => {
		expect(nameTokens('Petersen, Andrew')).toEqual(['petersen', 'andrew']);
		expect(nameTokens('Andrew Petersen').sort()).toEqual(nameTokens('Petersen, Andrew').sort());
	});

	test('strips accents, so an export and a profile need not agree about them', () => {
		expect(nameTokens('Muñoz')).toEqual(['munoz']);
	});

	test('splits hyphenated given names', () => {
		expect(nameTokens('Soh, Leen-Kiat')).toEqual(['soh', 'leen', 'kiat']);
	});
});

describe('matchPersonName', () => {
	test('reports an empty cell as naming nobody', () => {
		expect(matchPersonName('', [PETERSEN])).toEqual({ status: 'none' });
		expect(matchPersonName('   ', [PETERSEN])).toEqual({ status: 'none' });
	});

	test('resolves a name written in the other order', () => {
		expect(matchPersonName('Petersen, Andrew', [PETERSEN, SOH])).toEqual({
			status: 'resolved',
			id: 'p'
		});
	});

	test('resolves a hyphenated given name', () => {
		expect(matchPersonName('Soh, Leen-Kiat', [PETERSEN, SOH])).toEqual({
			status: 'resolved',
			id: 's'
		});
	});

	test('resolves across an accent difference', () => {
		expect(matchPersonName('Munoz, Ana', [MUNOZ])).toEqual({ status: 'resolved', id: 'm' });
	});

	test('resolves a name carrying a middle initial the profile lacks', () => {
		expect(matchPersonName('Petersen, Andrew J.', [PETERSEN, SOH])).toEqual({
			status: 'resolved',
			id: 'p'
		});
	});

	test('reports a name nobody matches', () => {
		expect(matchPersonName('Nobody, At All', [PETERSEN, SOH])).toEqual({ status: 'unmatched' });
	});

	// The whole point: never pick one of two people who both fit.
	test('never chooses between two candidates that fit equally well', () => {
		const twins: Candidate[] = [
			{ id: 'a', name: 'Andrew Petersen' },
			{ id: 'b', name: 'Andrew Petersen' }
		];
		const match = matchPersonName('Petersen, Andrew', twins);
		expect(match.status).toBe('ambiguous');
		expect(match.status === 'ambiguous' && match.candidates.map((c) => c.id)).toEqual(['a', 'b']);
	});

	test('reports two same-surname candidates sharing a first initial as ambiguous', () => {
		const both: Candidate[] = [
			{ id: 'a', name: 'Andrew Petersen' },
			{ id: 'b', name: 'Alice Petersen' }
		];
		expect(matchPersonName('Petersen, A. J.', both).status).toBe('ambiguous');
	});

	// An exact match must win outright rather than being dragged into ambiguity
	// by a weaker one.
	test('prefers an exact match over a surname-and-initial match', () => {
		const both: Candidate[] = [PETERSEN, { id: 'b', name: 'Alice Petersen' }];
		expect(matchPersonName('Andrew Petersen', both)).toEqual({ status: 'resolved', id: 'p' });
	});

	test('does not match on a shared surname alone', () => {
		expect(matchPersonName('Petersen', [PETERSEN])).toEqual({ status: 'unmatched' });
	});

	test('does not match on a substring of a name', () => {
		expect(matchPersonName('Pete', [PETERSEN])).toEqual({ status: 'unmatched' });
	});

	test('reports unmatched when there are no candidates at all', () => {
		expect(matchPersonName('Petersen, Andrew', [])).toEqual({ status: 'unmatched' });
	});
});

function volunteer(
	id: string,
	name: string,
	email: string | null = null,
	orcid: string | null = null
): Volunteer {
	return { id, name, email, orcid, affiliation: null };
}

describe('suggestCandidates', () => {
	const LEE = volunteer('lee', 'Scholar Lee');
	const EDITOR = volunteer('ed', 'Scholar Editor');
	const DANA = volunteer('dana', 'Dana Petersen');
	const ANDREW = volunteer('andrew', 'Andrew Petersen');

	test('ranks a misspelling of a surname above people who only share a given name', () => {
		expect(suggestCandidates('Scholar Leigh', [EDITOR, LEE]).map((c) => c.id)).toEqual([
			'lee',
			'ed'
		]);
	});

	test('finds a one-letter typo and either name order', () => {
		expect(suggestCandidates('Petersn, Andrew', [MUNOZ, ANDREW])[0]).toBe(ANDREW);
	});

	test('prefers the candidate whose initial agrees', () => {
		expect(suggestCandidates('A. Petersen', [DANA, ANDREW]).map((c) => c.id)).toEqual([
			'andrew',
			'dana'
		]);
	});

	test('never suggests on an initial alone', () => {
		expect(suggestCandidates('A. Zhao', [MUNOZ, ANDREW])).toEqual([]);
	});

	test('leaves out unrelated names', () => {
		expect(suggestCandidates('Wenjing Zhao', [LEE, DANA, MUNOZ])).toEqual([]);
	});

	test('breaks ties by name, so the order is stable', () => {
		const second = volunteer('lee2', 'Scholar Lee');
		const aaron = volunteer('aaron', 'Aaron Petersen');
		expect(suggestCandidates('Petersen', [DANA, ANDREW, aaron]).map((c) => c.id)).toEqual([
			'aaron',
			'andrew',
			'dana'
		]);
		expect(suggestCandidates('Scholar Lee', [second, LEE])).toHaveLength(2);
	});

	test('respects the limit', () => {
		const many = Array.from({ length: 10 }, (_, i) => volunteer(`${i}`, `Person ${i} Petersen`));
		expect(suggestCandidates('Petersen', many, 3)).toHaveLength(3);
	});

	test('suggests nothing for an empty name', () => {
		expect(suggestCandidates('  ', [LEE])).toEqual([]);
	});
});

describe('searchCandidates', () => {
	const ANDREW = volunteer(
		'andrew',
		'Andrew Petersen',
		'apetersen@cs.example.edu',
		'0000-0002-1825-0097'
	);
	const DANA = volunteer('dana', 'Dana Petersen', 'dana@example.org', null);
	const ANA = volunteer('ana', 'Ana Muñoz', 'ana@example.org', '0000-0001-5109-3700');

	test('matches the beginning of any word of the name, sorted by name', () => {
		expect(searchCandidates('peters', [DANA, ANA, ANDREW]).map((c) => c.id)).toEqual([
			'andrew',
			'dana'
		]);
	});

	test('needs every word typed', () => {
		expect(searchCandidates('dan pet', [DANA, ANDREW])).toEqual([DANA]);
	});

	test('does not match the middle of a name word', () => {
		expect(searchCandidates('ersen', [DANA, volunteer('a', 'Andrew Petersen')])).toEqual([]);
	});

	test('matches an email address or ORCID iD', () => {
		expect(searchCandidates('cs.example', [DANA, ANDREW])).toEqual([ANDREW]);
		expect(searchCandidates('0000-0001-5109', [ANA, ANDREW])).toEqual([ANA]);
	});

	test('ignores accents and case', () => {
		expect(searchCandidates('MUNOZ', [ANA, DANA])).toEqual([ANA]);
	});

	test('returns nothing for an empty query', () => {
		expect(searchCandidates('', [ANA])).toEqual([]);
	});
});
