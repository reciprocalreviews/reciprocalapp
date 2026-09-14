import { describe, expect, test } from 'vitest';
import {
	affiliationLine,
	educationLine,
	hasAnything,
	shouldReportProblem,
	worksStat
} from './orcidProfileView';

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
