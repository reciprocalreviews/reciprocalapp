import { describe, expect, test } from 'vitest';
import { loginHref, safeNext } from './next';

describe('safeNext', () => {
	test('keeps a path on this site, with its query and fragment', () => {
		expect(safeNext('/scholar/abc#notifications-reviewing')).toBe(
			'/scholar/abc#notifications-reviewing'
		);
		expect(safeNext('/venue/knowledge/submissions?x=1')).toBe('/venue/knowledge/submissions?x=1');
	});
	test('refuses anything that could leave the site', () => {
		for (const value of [
			'//evil.example',
			'/\\evil.example',
			'https://evil.example',
			'javascript:alert(1)',
			'evil.example',
			'/\t/evil.example',
			'/ok\nLocation: x',
			'',
			null,
			undefined,
			'/' + 'a'.repeat(600)
		])
			expect(safeNext(value), String(value)).toBeNull();
	});
});

describe('loginHref', () => {
	test('comes back to the page it was offered on', () => {
		const href = loginHref(new URL('https://reciprocal.reviews/venue/v/submission/s?tab=1#bids'));
		expect(href).toBe(`/login?next=${encodeURIComponent('/venue/v/submission/s?tab=1#bids')}`);
		expect(safeNext(new URL(href, 'https://x.invalid').searchParams.get('next'))).toBe(
			'/venue/v/submission/s?tab=1#bids'
		);
	});
	test('accepts a bare path', () => {
		expect(loginHref('/scholar/abc')).toBe(`/login?next=${encodeURIComponent('/scholar/abc')}`);
	});
	test('has nowhere to come back to from the landing page or the login page', () => {
		for (const path of ['/', '/en', '/login', '/en/login', '/login?next=%2Fscholar%2Fabc'])
			expect(loginHref(path), path).toBe('/login');
	});
});
