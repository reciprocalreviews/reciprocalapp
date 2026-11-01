import { describe, expect, test } from 'vitest';
import {
	matchesRelevantVenue,
	parseRelevantVenues,
	previewRelevantVenues,
	trackRecord,
	trackTier,
	venueJournals,
	venueWords
} from './trackRecord';

const SIGCSE_PROCEEDINGS =
	'Proceedings of the 55th ACM Technical Symposium on Computer Science Education V. 1';
const ICER_PROCEEDINGS =
	'Proceedings of the 2023 ACM Conference on International Computing Education Research - Volume 1';

describe('venueWords', () => {
	test('drops case, punctuation, filler, ordinals and numbers', () => {
		expect(venueWords(SIGCSE_PROCEEDINGS)).toEqual([
			'technical',
			'symposium',
			'computer',
			'science',
			'education'
		]);
	});

	test('splits letters from digits and strips accents', () => {
		expect(venueWords('ICER2023')).toEqual(['icer']);
		expect(venueWords('Éducation')).toEqual(['education']);
	});
});

describe('matchesRelevantVenue', () => {
	test.each([
		[SIGCSE_PROCEEDINGS, 'ACM Technical Symposium on Computer Science Education', true],
		["SIGCSE '24", 'SIGCSE', true],
		['ACM Trans. Comput. Educ.', 'ACM Transactions on Computing Education', true],
		['ACM Transactions on Computing Education', 'Trans. Comput. Educ.', true],
		[ICER_PROCEEDINGS, 'ICER', false],
		[ICER_PROCEEDINGS, 'International Computing Education Research', true],
		['ICER2023', 'ICER', true],
		['Officer Training Quarterly', 'ICER', false],
		['ICERI2023 Proceedings', 'ICER', false],
		['ACM Transactions on Computational Logic', 'ACM Transactions on Computing Education', false],
		['ACM Trans. Comput.-Hum. Interact.', 'ACM Transactions on Computing Education', false]
	])('%s ~ %s: %s', (title, name, expected) => {
		expect(matchesRelevantVenue(title, [name])).toBe(expected);
	});

	test('any of a line’s names matches', () => {
		expect(
			matchesRelevantVenue(ICER_PROCEEDINGS, ['ICER, International Computing Education Research'])
		).toBe(true);
	});
});

describe('parseRelevantVenues', () => {
	test('one venue per line, names tidied, blanks and duplicates dropped', () => {
		expect(
			parseRelevantVenues('ACM Transactions on Computing Education ,  TOCE\n\n , \nSIGCSE\nsigcse')
		).toEqual(['ACM Transactions on Computing Education, TOCE', 'SIGCSE']);
	});
});

const journals = [
	{ journal: 'ACM Transactions on Computing Education', count: 3 },
	{ journal: SIGCSE_PROCEEDINGS, count: 2 },
	{ journal: 'Officer Training Quarterly', count: 4 },
	{ journal: 'IEEE Transactions on Software Engineering', count: 5 }
];

describe('venueJournals', () => {
	test('no lines matches nothing', () => {
		expect(venueJournals(journals, [])).toEqual([]);
	});
});

describe('trackRecord', () => {
	test('reviewed here outranks publishing, which outranks neither', () => {
		expect(trackTier(trackRecord(1, [], ['TOCE']))).toBe(0);
		expect(trackTier(trackRecord(0, journals, ['Computer Science Education']))).toBe(1);
		expect(trackTier(trackRecord(0, journals, ['ICER']))).toBe(2);
	});

	test('counts works across every matched journal', () => {
		expect(
			trackRecord(0, journals, ['Transactions on Computing Education, TOCE', 'Technical Symposium'])
				.venueWorks
		).toBe(5);
	});
});

describe('previewRelevantVenues', () => {
	test('counts scholars and lists titles per line', () => {
		const preview = previewRelevantVenues(
			['TOCE, Transactions on Computing Education', 'ICER'],
			[
				{ scholar: 'a', journals },
				{ scholar: 'b', journals: [{ journal: 'ACM Trans. Comput. Educ.', count: 1 }] }
			]
		);
		expect(preview).toEqual([
			{
				line: 'TOCE, Transactions on Computing Education',
				scholars: 2,
				titles: ['ACM Transactions on Computing Education', 'ACM Trans. Comput. Educ.']
			},
			{ line: 'ICER', scholars: 0, titles: [] }
		]);
	});
});
