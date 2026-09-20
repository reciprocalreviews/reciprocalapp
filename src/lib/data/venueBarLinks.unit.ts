import en from '$locales/en.json';
import type { LocaleText } from '$lib/locales/Locale';
import { describe, expect, test } from 'vitest';
import { venueBarLinks, venueBarName, type VenueBarVenue } from './venueBarLinks';

const locale = en as LocaleText;

const ADMIN = 'admin-scholar-id';
const OTHER = 'other-scholar-id';

function venue(overrides: Partial<VenueBarVenue> = {}): VenueBarVenue {
	return {
		id: '11111111-2222-3333-4444-555555555555',
		slug: 'knowledge',
		title: 'Transactions on Knowledge',
		short_title: 'ToK',
		url: 'https://tok.science.org',
		payment_free: false,
		admins: [ADMIN],
		...overrides
	};
}

const labels = (v: VenueBarVenue, scholar: string | null) =>
	venueBarLinks(v, scholar, locale).map((l) => l.label);

describe('venueBarName', () => {
	test('prefers the short name', () => {
		expect(venueBarName({ title: 'Transactions on Knowledge', short_title: 'ToK' })).toBe('ToK');
	});

	test('falls back to the full title when no short name was chosen', () => {
		// Empty rather than null is the unset state, matching the column's default.
		expect(venueBarName({ title: 'Transactions on Knowledge', short_title: '' })).toBe(
			'Transactions on Knowledge'
		);
	});
});

describe('venueBarLinks', () => {
	test('an admin sees every link', () => {
		expect(labels(venue(), ADMIN)).toEqual([
			'Submissions',
			'Volunteers',
			'Transactions',
			'Settings',
			'Website'
		]);
	});

	test('settings is admin-only', () => {
		expect(labels(venue(), OTHER)).not.toContain('Settings');
		expect(labels(venue(), null)).not.toContain('Settings');
	});

	test('a payment-free venue offers no transactions', () => {
		// The rest of the app hides every token surface for such a venue, so a ledger link
		// would lead to a page about a currency it does not use.
		expect(labels(venue({ payment_free: true }), ADMIN)).toEqual([
			'Submissions',
			'Volunteers',
			'Settings',
			'Website'
		]);
	});

	test('a venue with no website offers no website link', () => {
		expect(labels(venue({ url: '' }), ADMIN)).not.toContain('Website');
	});

	test('links are built from the web address when there is one, and the id otherwise', () => {
		expect(venueBarLinks(venue(), null, locale)[0].href).toBe('/venue/knowledge/submissions');
		expect(venueBarLinks(venue({ slug: null }), null, locale)[0].href).toBe(
			'/venue/11111111-2222-3333-4444-555555555555/submissions'
		);
	});

	test('only the venue website leaves the app', () => {
		const links = venueBarLinks(venue(), ADMIN, locale);
		expect(links.filter((l) => l.external).map((l) => l.href)).toEqual(['https://tok.science.org']);
	});

	test('the everyday links stay in the row; the rest may collapse', () => {
		const links = venueBarLinks(venue(), ADMIN, locale);
		expect(links.filter((l) => !l.overflow).map((l) => l.label)).toEqual([
			'Submissions',
			'Volunteers'
		]);
	});
});
