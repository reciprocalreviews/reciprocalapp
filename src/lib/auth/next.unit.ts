import { describe, expect, test } from 'vitest';
import { safeNext } from './next';

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
