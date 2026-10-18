import { describe, expect, test } from 'vitest';
import en from '$locales/en.json';
import type { LocaleText } from '#lib/locales/Locale.js';
import { areaDrawsBar, currencyBar, scholarBar, siteBar, venuesBar } from './contextBar';

const locale: LocaleText = en;

describe('areaDrawsBar', () => {
	test('venue, venues, scholar and currency routes draw their own', () => {
		expect(areaDrawsBar('/[[lang]]/venue/[venueid]/submissions')).toBe(true);
		expect(areaDrawsBar('/[[lang]]/venues')).toBe(true);
		expect(areaDrawsBar('/[[lang]]/venues/proposal/[id]')).toBe(true);
		expect(areaDrawsBar('/[[lang]]/scholar/[id]/transactions')).toBe(true);
		expect(areaDrawsBar('/[[lang]]/currency/[id]')).toBe(true);
	});

	test('everything else, and error pages, get the site bar', () => {
		expect(areaDrawsBar('/')).toBe(false);
		expect(areaDrawsBar('/[[lang]]/about')).toBe(false);
		expect(areaDrawsBar('/[[lang]]/help/[slug]')).toBe(false);
		expect(areaDrawsBar(null)).toBe(false);
	});
});

describe('bars', () => {
	test('proposing a venue is offered only to someone signed in', () => {
		expect(venuesBar(locale, false).links).toEqual([]);
		expect(venuesBar(locale, true).links.map((l) => l.href)).toEqual(['/venues/proposal']);
	});

	test('a scholar with no name is named by their ORCID iD, then generically', () => {
		expect(scholarBar({ id: 'a', name: null, orcid: '0000-0001' }, locale).name).toBe('0000-0001');
		expect(scholarBar({ id: 'a', name: null, orcid: null }, locale).name).toBe(
			locale.page.scholar.title
		);
	});

	test('scholar and currency bars reach their transactions', () => {
		expect(scholarBar({ id: 'a', name: 'A', orcid: null }, locale).links[0].href).toBe(
			'/scholar/a/transactions'
		);
		expect(currencyBar({ id: 'c', name: 'C' }, locale).links[0].href).toBe(
			'/currency/c/transactions'
		);
	});

	test('the site bar goes home', () => {
		expect(siteBar(locale).href).toBe('/');
	});
});
