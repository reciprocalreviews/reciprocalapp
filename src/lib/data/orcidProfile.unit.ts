import { describe, expect, test } from 'vitest';
import emptyEducations from './orcid-fixtures/empty-educations.json';
import emptyEmployments from './orcid-fixtures/empty-employments.json';
import emptyPerson from './orcid-fixtures/empty-person.json';
import emptyWorks from './orcid-fixtures/empty-works.json';
import fullEducations from './orcid-fixtures/full-educations.json';
import fullEmployments from './orcid-fixtures/full-employments.json';
import fullPerson from './orcid-fixtures/full-person.json';
import fullWorks from './orcid-fixtures/full-works.json';
import sparseEducations from './orcid-fixtures/sparse-educations.json';
import sparseEmployments from './orcid-fixtures/sparse-employments.json';
import sparsePerson from './orcid-fixtures/sparse-person.json';
import sparseWorks from './orcid-fixtures/sparse-works.json';
import {
	buildProfile,
	MAX_WORKS,
	orcidAPIURL,
	parseEducations,
	parseEmployments,
	parsePerson,
	parseWorks
} from './orcidProfile';

/** The fixtures are real responses from pub.orcid.org, captured once and committed so
 * these tests never touch the network. `full` is a mid-career record (46 works trimmed
 * to 8 groups, keeping the three that hold more than one summary), `sparse` a new one,
 * `empty` a synthesised record with every section present and nothing in it. */

describe('works', () => {
	test('counts groups, not summaries', () => {
		// The trap this exists for: one work claimed by Crossref, by Scopus and by the
		// scholar is three summaries in ONE group. The fixture holds 8 groups across 12
		// summaries, so a parser counting summaries answers 12.
		const summaries = fullWorks.group.reduce((n, g) => n + g['work-summary'].length, 0);
		expect(summaries).toBe(12);
		expect(parseWorks(fullWorks).workCount).toBe(8);
	});

	test('keeps at most MAX_WORKS, newest first', () => {
		const { works } = parseWorks(fullWorks);
		expect(works).toHaveLength(MAX_WORKS);
		const years = works.map((w) => w.year);
		expect([...years].sort((a, b) => (b ?? 0) - (a ?? 0))).toEqual(years);
	});

	test('spans every work, not only the ones kept', () => {
		const { works, workFirstYear, workLastYear } = parseWorks(fullWorks);
		// 2021 is outside the five kept, so a span computed from `works` would miss it.
		expect(workFirstYear).toBe(2021);
		expect(workLastYear).toBe(2027);
		expect(Math.min(...works.map((w) => w.year ?? Infinity))).toBeGreaterThan(workFirstYear!);
	});

	test('prefers the most complete summary in a group', () => {
		// Group 16 of the real record: Crossref's copy carries no journal title, the
		// scholar's own does. Picking by put-code alone would take the Crossref one.
		const multi = fullWorks.group.find((g) => g['work-summary'].length > 1)!;
		const parsed = parseWorks({ group: [multi] });
		const withJournal = multi['work-summary'].some(
			(s: Record<string, unknown>) => s['journal-title'] !== null
		);
		if (withJournal) expect(parsed.works[0].journal).not.toBeNull();
	});

	test('picks the same summary whichever order they arrive in', () => {
		const multi = fullWorks.group.find((g) => g['work-summary'].length > 2)!;
		const forwards = parseWorks({ group: [multi] }).works[0];
		const backwards = parseWorks({
			group: [{ ...multi, 'work-summary': [...multi['work-summary']].reverse() }]
		}).works[0];
		expect(backwards).toEqual(forwards);
	});

	test('links a DOI in preference to the record url', () => {
		const { works } = parseWorks(fullWorks);
		const withDoi = works.find((w) => w.doi !== null)!;
		expect(withDoi.url).toBe(`https://doi.org/${withDoi.doi}`);
	});

	test('an undated work sorts last and does not poison the span', () => {
		const { works, workFirstYear, workLastYear } = parseWorks({
			group: [
				{ 'work-summary': [{ title: { title: { value: 'Undated' } }, 'publication-date': null }] },
				{
					'work-summary': [
						{
							title: { title: { value: 'Dated' } },
							'publication-date': { year: { value: '2011' } }
						}
					]
				}
			]
		});
		expect(works.map((w) => w.title)).toEqual(['Dated', 'Undated']);
		expect([workFirstYear, workLastYear]).toEqual([2011, 2011]);
	});

	test('a work with no title is dropped rather than rendered blank', () => {
		const { works, workCount } = parseWorks({
			group: [
				{ 'work-summary': [{ title: { title: { value: '   ' } } }] },
				{ 'work-summary': [{ title: { title: { value: 'Real' } } }] }
			]
		});
		expect(works.map((w) => w.title)).toEqual(['Real']);
		// Still counted: the record holds two works, we can only display one of them.
		expect(workCount).toBe(2);
	});

	test('an empty works section is 0, never null', () => {
		// Null means "not read". They are different states and the interface branches
		// on the difference, so this is the assertion that keeps them apart.
		const { workCount, works } = parseWorks(emptyWorks);
		expect(workCount).toBe(0);
		expect(works).toEqual([]);
	});
});

describe('employments', () => {
	test('reads the current post', () => {
		const employment = parseEmployments(fullEmployments);
		expect(employment.employmentOrganization).toBe('University of Washington');
		expect(employment.employmentRole).toBe('Professor');
		expect(employment.employmentDepartment).toBe('The Information School');
	});

	test('a current post beats a more recently ended one', () => {
		const employment = parseEmployments({
			'affiliation-group': [
				{
					summaries: [
						{
							'employment-summary': {
								'role-title': 'Ended last year',
								organization: { name: 'Elsewhere' },
								'start-date': { year: { value: '2015' } },
								'end-date': { year: { value: '2024' } }
							}
						},
						{
							'employment-summary': {
								'role-title': 'Still there',
								organization: { name: 'Here' },
								'start-date': { year: { value: '2009' } },
								'end-date': null
							}
						}
					]
				}
			]
		});
		expect(employment.employmentOrganization).toBe('Here');
	});

	test('falls back to the latest-ended post when none is current', () => {
		const employment = parseEmployments({
			'affiliation-group': [
				{
					summaries: [
						{
							'employment-summary': {
								organization: { name: 'Older' },
								'end-date': { year: { value: '2001' } }
							}
						},
						{
							'employment-summary': {
								organization: { name: 'Newer' },
								'end-date': { year: { value: '2019' } }
							}
						}
					]
				}
			]
		});
		expect(employment.employmentOrganization).toBe('Newer');
	});

	test('an empty section yields nulls, not empty strings', () => {
		expect(parseEmployments(emptyEmployments)).toEqual({
			employmentRole: null,
			employmentDepartment: null,
			employmentOrganization: null
		});
	});
});

describe('educations', () => {
	test('reads the degree and institution', () => {
		const education = parseEducations(fullEducations);
		expect(education.educationOrganization).toBe('Carnegie Mellon University');
		expect(education.educationRole).toContain('Ph.D.');
	});

	test('takes the year from a date carrying no month or day', () => {
		const education = parseEducations({
			'affiliation-group': [
				{
					summaries: [
						{
							'education-summary': {
								organization: { name: 'Somewhere' },
								'start-date': { year: { value: '2002' }, month: null, day: null },
								'end-date': null
							}
						}
					]
				}
			]
		});
		expect(education.educationYear).toBe(2002);
	});
});

describe('person', () => {
	test('reads keywords in the spelling the record uses', () => {
		expect(parsePerson(fullPerson).keywords).toEqual([
			'computing education',
			'human-computer interaction',
			'software engineering'
		]);
	});

	test('de-duplicates keywords case-insensitively', () => {
		const { keywords } = parsePerson({
			keywords: { keyword: [{ content: 'HCI' }, { content: 'hci' }, { content: '  ' }] }
		});
		expect(keywords).toEqual(['HCI']);
	});

	test('reads researcher urls and external identifiers as links', () => {
		const { links } = parsePerson(fullPerson);
		expect(links.some((l) => l.kind === 'url' && l.label === 'Faculty website')).toBe(true);
		expect(links.some((l) => l.kind === 'identifier' && l.label === 'Scopus Author ID')).toBe(true);
	});

	test('a url with no name is labelled with itself', () => {
		const { links } = parsePerson({
			'researcher-urls': {
				'researcher-url': [{ 'url-name': null, url: { value: 'https://x.test' } }]
			}
		});
		expect(links[0].label).toBe('https://x.test');
	});

	test('reads no email, whatever the record publishes', () => {
		// ORCID does publish public verified addresses, and the full fixture has one.
		// RR verifies its own (#27) and must never adopt one it did not.
		expect(JSON.stringify(parsePerson(fullPerson))).not.toContain('@');
	});
});

describe('whole records', () => {
	test('a sparse record parses without inventing anything', () => {
		const profile = buildProfile({
			person: sparsePerson,
			employments: sparseEmployments,
			educations: sparseEducations,
			works: sparseWorks
		});
		expect(profile.keywords).toEqual([]);
		expect(profile.employmentOrganization).toBeNull();
		expect(profile.workCount).toBe(7);
	});

	test('an empty record parses to a well-formed profile', () => {
		const profile = buildProfile({
			person: emptyPerson,
			employments: emptyEmployments,
			educations: emptyEducations,
			works: emptyWorks
		});
		expect(profile.keywords).toEqual([]);
		expect(profile.works).toEqual([]);
		expect(profile.workCount).toBe(0);
		expect(profile.employmentOrganization).toBeNull();
	});

	test('omitting a section leaves its fields absent rather than null', () => {
		// What a partly-failed refresh relies on: the caller keeps whatever it already
		// had for the sections that did not come back.
		const profile = buildProfile({ person: fullPerson });
		expect(profile.keywords).toHaveLength(3);
		expect('employmentOrganization' in profile).toBe(false);
		expect('workCount' in profile).toBe(false);
	});

	test('garbage parses to nothing rather than throwing', () => {
		// A shape change upstream must degrade one scholar, not throw inside a batch
		// and lose the rest of it.
		for (const junk of [null, 'nope', 42, [], { group: 'not an array' }]) {
			expect(() => buildProfile({ person: junk, works: junk })).not.toThrow();
		}
	});
});

test('builds section urls', () => {
	expect(orcidAPIURL('0000-0001-7461-4783', 'works')).toBe(
		'https://pub.orcid.org/v3.0/0000-0001-7461-4783/works'
	);
});
