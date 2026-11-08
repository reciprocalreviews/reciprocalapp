import { describe, expect, test } from 'vitest';
import {
	affiliationLine,
	educationLine,
	hasAnything,
	links,
	shouldReportProblem,
	works,
	worksStat
} from './orcidProfileView';
import type { ORCIDWork } from './orcidProfile';

describe('affiliationLine', () => {
	// All eight subsets of the three parts. Joining strings is where the stray-comma bugs
	// live, and they are only visible on the combinations nobody thinks to look at.
	const cases: [string | null, string | null, string | null, string | null][] = [
		['Professor', 'The iSchool', 'UW', 'Professor, The iSchool, UW'],
		['Professor', 'The iSchool', null, 'Professor, The iSchool'],
		['Professor', null, 'UW', 'Professor, UW'],
		[null, 'The iSchool', 'UW', 'The iSchool, UW'],
		['Professor', null, null, 'Professor'],
		[null, 'The iSchool', null, 'The iSchool'],
		[null, null, 'UW', 'UW'],
		[null, null, null, null]
	];
	for (const [role, department, organization, expected] of cases)
		test(`${role} / ${department} / ${organization}`, () => {
			expect(
				affiliationLine({
					employment_role: role,
					employment_department: department,
					employment_organization: organization
				})
			).toBe(expected);
		});

	test('drops the department in short form', () => {
		expect(
			affiliationLine(
				{
					employment_role: 'Professor',
					employment_department: 'The iSchool',
					employment_organization: 'UW'
				},
				true
			)
		).toBe('Professor, UW');
	});

	test('treats whitespace as absent', () => {
		expect(
			affiliationLine({
				employment_role: '  ',
				employment_department: null,
				employment_organization: 'UW'
			})
		).toBe('UW');
	});

	test('is null for an absent profile', () => {
		expect(affiliationLine(null)).toBeNull();
		expect(affiliationLine(undefined)).toBeNull();
	});
});

describe('educationLine', () => {
	test('joins degree, institution and year', () => {
		expect(
			educationLine({
				education_role: 'Ph.D.',
				education_organization: 'CMU',
				education_year: 2008
			})
		).toBe('Ph.D., CMU, 2008');
	});

	test('omits a missing year without a trailing comma', () => {
		expect(
			educationLine({
				education_role: 'Ph.D.',
				education_organization: 'CMU',
				education_year: null
			})
		).toBe('Ph.D., CMU');
	});
});

describe('worksStat', () => {
	test('counts and spans', () => {
		expect(worksStat({ work_count: 46, work_first_year: 2004, work_last_year: 2025 })).toBe(
			'46 works, 2004–2025'
		);
	});

	test('a single work is singular', () => {
		expect(worksStat({ work_count: 1, work_first_year: 2020, work_last_year: 2020 })).toBe(
			'1 work, 2020'
		);
	});

	test('one year is a year, not a range', () => {
		expect(worksStat({ work_count: 3, work_first_year: 2024, work_last_year: 2024 })).toBe(
			'3 works, 2024'
		);
	});

	test('a count with no dated works is still a count', () => {
		expect(worksStat({ work_count: 4, work_first_year: null, work_last_year: null })).toBe(
			'4 works'
		);
	});

	test('read and empty is "No works"', () => {
		expect(worksStat({ work_count: 0 })).toBe('No works');
	});

	test('unread is null, which is NOT the same as zero', () => {
		// The distinction the whole nullable column exists for.
		expect(worksStat({ work_count: null })).toBeNull();
		expect(worksStat({})).toBeNull();
	});
});

describe('hasAnything', () => {
	test('false for absent, empty, and an all-null row', () => {
		expect(hasAnything(null)).toBe(false);
		expect(hasAnything({})).toBe(false);
		expect(
			hasAnything({
				employment_role: null,
				employment_organization: null,
				education_role: null,
				keywords: [],
				works: [],
				links: [],
				work_count: null
			})
		).toBe(false);
	});

	test('true on any one signal alone', () => {
		expect(hasAnything({ employment_organization: 'UW' })).toBe(true);
		expect(hasAnything({ keywords: ['hci'] })).toBe(true);
		expect(
			hasAnything({ works: [{ title: 'A', year: null, journal: null, doi: null, url: null }] })
		).toBe(true);
		expect(hasAnything({ links: [{ kind: 'url', label: 'x', value: 'y', url: 'y' }] })).toBe(true);
		// A record read and found to have no works is a fact, not an absence.
		expect(hasAnything({ work_count: 0 })).toBe(true);
	});
});

describe('shouldReportProblem', () => {
	test('only for a failed or missing record', () => {
		expect(shouldReportProblem({ fetch_status: 'not_found' })).toBe(true);
		expect(shouldReportProblem({ fetch_status: 'error' })).toBe(true);
		expect(shouldReportProblem({ fetch_status: 'ok' })).toBe(false);
		expect(shouldReportProblem({ fetch_status: 'pending' })).toBe(false);
		expect(shouldReportProblem(null)).toBe(false);
	});
});

/**
 * The two lists, and what counts as the same entry in each.
 *
 * These exist because an ORCID record may legally list the same identifier or the same paper
 * twice, and the profile section used to key its `{#each}` blocks on that content — which
 * throws, escapes hydration, and leaves the entire page drawn and wired to nothing. The keys
 * are gone, so a duplicate can no longer break a page; these are what keep it from being SHOWN
 * twice, on the rows already mirrored as well as on the ones written from here on.
 */
describe('links', () => {
	const researcherID = {
		kind: 'identifier' as const,
		label: 'ResearcherID',
		value: 'D-1001-2018',
		url: null
	};
	const scopus = {
		kind: 'identifier' as const,
		label: 'Scopus Author ID',
		value: '56732624800',
		url: null
	};

	test('the record that broke a profile page', () => {
		// Transcribed from the real record: the same ResearcherID either side of a Scopus id.
		expect(links({ links: [researcherID, scopus, { ...researcherID, url: 'https://x' }] })).toEqual(
			[researcherID, scopus]
		);
	});

	test('the same url twice is one link, named or not', () => {
		// `parseLinks` falls back to the url as the label, so one address can arrive under two
		// spellings. The label is not part of a url's identity for exactly that reason.
		expect(
			links({
				links: [
					{ kind: 'url', label: 'Home page', value: 'https://a.example', url: 'https://a.example' },
					{
						kind: 'url',
						label: 'https://a.example',
						value: 'https://a.example',
						url: 'https://a.example'
					}
				]
			})
		).toEqual([
			{ kind: 'url', label: 'Home page', value: 'https://a.example', url: 'https://a.example' }
		]);
	});

	test('two registries issuing the same string are two identifiers', () => {
		const pair = [
			{ kind: 'identifier' as const, label: 'ResearcherID', value: '12345', url: null },
			{ kind: 'identifier' as const, label: 'Scopus Author ID', value: '12345', url: null }
		];
		expect(links({ links: pair })).toEqual(pair);
	});

	test('a url and an identifier sharing a value are both kept', () => {
		const pair = [
			{ kind: 'url' as const, label: 'x', value: '12345', url: null },
			{ kind: 'identifier' as const, label: 'ResearcherID', value: '12345', url: null }
		];
		expect(links({ links: pair })).toEqual(pair);
	});

	test('absent on a list query', () => {
		expect(links(null)).toEqual([]);
		expect(links(undefined)).toEqual([]);
		expect(links({})).toEqual([]);
	});
});

describe('works', () => {
	const work = (over: Partial<ORCIDWork>): ORCIDWork => ({
		title: 'On Rigor',
		year: 2024,
		journal: 'TOCE',
		doi: null,
		url: null,
		...over
	});

	test('a normal list passes through, in order', () => {
		const list = [work({ title: 'B' }), work({ title: 'A' })];
		expect(works({ works: list })).toEqual(list);
	});

	test('the same title, year and journal is one work', () => {
		expect(works({ works: [work({ url: 'first' }), work({ url: 'second' })] })).toEqual([
			work({ url: 'first' })
		]);
	});

	test('one DOI is one work, however it is spelled or titled', () => {
		expect(
			works({
				works: [
					work({ title: 'Preprint', doi: '10.1109/ACCESS.2024.3521237' }),
					work({ title: 'Published', doi: '10.1109/access.2024.3521237' })
				]
			})
		).toEqual([work({ title: 'Preprint', doi: '10.1109/ACCESS.2024.3521237' })]);
	});

	test('different DOIs are different works, however alike they read', () => {
		// The conservative half, and deliberate: a preprint and its published version are two
		// entries in the record and stay two here. Merging them would need a judgement this
		// has no basis to make.
		const pair = [work({ doi: '10.1/a' }), work({ doi: '10.1/b' })];
		expect(works({ works: pair })).toEqual(pair);
	});

	test('without a DOI, year and journal are what tell two works apart', () => {
		// "Editorial" is a real title that one person may hold several distinct instances of,
		// which is why title alone is not the identity.
		const pair = [
			work({ title: 'Editorial', year: 2024 }),
			work({ title: 'Editorial', year: 2023 })
		];
		expect(works({ works: pair })).toEqual(pair);

		const journals = [
			work({ title: 'Editorial', journal: 'TOCE' }),
			work({ title: 'Editorial', journal: 'FIE' })
		];
		expect(works({ works: journals })).toEqual(journals);
	});

	test('spelling of the title does not make a second work', () => {
		expect(
			works({ works: [work({ title: '  On   Rigor ' }), work({ title: 'on rigor' })] })
		).toEqual([work({ title: '  On   Rigor ' })]);
	});

	test('a malformed entry does not take the page down with it', () => {
		// These columns are jsonb, and the keys are now computed while the page renders. A throw
		// here would be the very failure this deduplication was added alongside — a page that
		// renders and does nothing — so an entry with no title is passed through rather than
		// being asked for a key it cannot give.
		expect(
			works({ works: [{ url: 'https://a.example' }, { title: null, year: 2020 }] })
		).toHaveLength(2);
		expect(links({ links: [{ kind: 'identifier' }, { kind: 'url' }] })).toHaveLength(2);
	});

	test('absent on a list query', () => {
		expect(works(null)).toEqual([]);
		expect(works(undefined)).toEqual([]);
		expect(works({})).toEqual([]);
	});
});
