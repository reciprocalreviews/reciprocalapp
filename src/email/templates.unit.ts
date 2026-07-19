import { describe, expect, it } from 'vitest';
import { renderEmail } from './templates';

describe('renderEmail', () => {
	it('escapes markup in argument values', () => {
		const { message } = renderEmail('VenueApproved', ['<script>alert(1)</script>', 'venue-id']);
		expect(message).not.toContain('<script>');
		expect(message).toContain('&lt;script&gt;');
	});

	it('defangs URLs in untrusted arguments so they cannot be auto-linked', () => {
		// paragraphsToHtml auto-links bare `https://` text at send time, so an argument
		// carrying a URL would otherwise arrive as a real link in branded mail.
		const { message } = renderEmail('VenueApproved', ['https://example.invalid/steal', 'v']);
		expect(message).toContain('https[:]//example.invalid/steal');
		expect(message).not.toContain('https://example.invalid');
	});

	it('leaves template-owned URLs intact', () => {
		const { message } = renderEmail('VenueApproved', ['A venue', 'venue-id']);
		expect(message).toContain('https://reciprocal.reviews/venue/venue-id');
	});

	it('keeps a declared URL argument clickable', () => {
		// VerifyEmail declares urlArgs: [1] — the link is built server-side, not by a caller.
		const { message } = renderEmail('VerifyEmail', ['https://reciprocal.reviews/verify/abc123']);
		expect(message).toContain('https://reciprocal.reviews/verify/abc123');
		expect(message).not.toContain('[:]');
	});

	it('substitutes every occurrence of a placeholder, not just the first', () => {
		const { message } = renderEmail('RoleInvite', ['Reviewer', 'venue-id', 'Venue', 'scholar-id']);
		// $2 appears once and $4 once, but $1/$3 are what we can see repeated in prose;
		// assert no unsubstituted placeholder survives anywhere.
		expect(message).not.toMatch(/\$\d/);
	});

	it('leaves an unknown placeholder as written rather than rendering undefined', () => {
		const { message } = renderEmail('VenueApproved', ['Only one arg']);
		expect(message).not.toContain('undefined');
		expect(message).toContain('$2');
	});
});
