import { describe, expect, test } from 'vitest';
import { matchPersonName, nameTokens, type Candidate } from './matchPersonName';

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
