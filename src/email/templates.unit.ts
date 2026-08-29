import { describe, expect, it } from 'vitest';
import { Emails, OptionalEmails, renderEmail, type EmailType } from './templates';
import en from '../../static/locales/en.json';

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

	it('sends links to the origin it is given', () => {
		// Templates used to hardcode production, so mail from a local stack or
		// staging pointed at reciprocal.reviews — which made every flow that
		// arrives by email untestable anywhere but production.
		const { message } = renderEmail(
			'VenueApproved',
			['A venue', 'venue-id'],
			'http://localhost:5173'
		);
		expect(message).toContain('http://localhost:5173/venue/venue-id');
		expect(message).not.toContain('reciprocal.reviews');
	});

	it('falls back to production when no origin is given', () => {
		// An unconfigured project keeps sending the links it always sent.
		const { message } = renderEmail('VenueApproved', ['A venue', 'venue-id']);
		expect(message).toContain('https://reciprocal.reviews/venue/venue-id');
	});

	it('ignores a trailing slash on the origin', () => {
		const { message } = renderEmail(
			'VenueApproved',
			['A venue', 'venue-id'],
			'http://localhost:5173/'
		);
		expect(message).toContain('http://localhost:5173/venue/venue-id');
		expect(message).not.toContain('5173//venue');
	});

	it('does not expand {origin} appearing inside an argument value', () => {
		// The origin is resolved in the template before arguments are substituted,
		// so a venue title containing the literal token stays literal.
		const { message } = renderEmail('VenueApproved', ['{origin}', 'venue-id'], 'http://local');
		expect(message).toContain('{origin}');
	});

	it('keeps the decline link clickable', () => {
		// TransactionDeclined passes its link as an argument, and arguments are
		// defanged unless the template declares the position trusted — so these
		// emails shipped a visibly mangled, unclickable link.
		const { message } = renderEmail('TransactionDeclined', [
			'purpose',
			'3',
			'Tokens',
			'Decliner',
			'decliner@uni.edu',
			'reason',
			'https://reciprocal.reviews/scholar/abc/transactions'
		]);
		expect(message).toContain('https://reciprocal.reviews/scholar/abc/transactions');
		expect(message).not.toContain('[:]');
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

describe('NewVolunteer', () => {
	const args = ['Ada Lovelace', 'Reviewer', 'TOCE', 'scholar-id', 'venue-id', 'Area Chair'];

	// The priority-0 role is called whatever the venue calls it — "Editor", "Area Chair",
	// "Associate Editor". Writing a word into the prose would be wrong for most venues, so
	// the name is an argument resolved from the row.
	it("names the venue's own word for its top role", () => {
		const { message } = renderEmail('NewVolunteer', args);
		expect(message).toContain('Area Chair');
		expect(message).not.toContain('Editor');
	});

	it('names the volunteer, the role they took, and the venue', () => {
		const { subject, message } = renderEmail('NewVolunteer', args);
		expect(subject).toContain('TOCE');
		expect(message).toContain('Ada Lovelace');
		expect(message).toContain('Reviewer');
	});

	it('links to the volunteer and to the venue roster', () => {
		const { message } = renderEmail('NewVolunteer', args, 'http://localhost:5173');
		expect(message).toContain('http://localhost:5173/scholar/scholar-id');
		expect(message).toContain('http://localhost:5173/venue/venue-id/volunteers');
	});

	// The name is the one value here a scholar chooses, and it lands in genuinely branded
	// mail from notifications@reciprocal.reviews. A live link in it would be phishing.
	it("defangs a link hiding in the volunteer's name", () => {
		const { message } = renderEmail('NewVolunteer', ['https://evil.example', ...args.slice(1)]);
		expect(message).toContain('https[:]//evil.example');
		expect(message).not.toContain('https://evil.example');
	});

	it('substitutes every placeholder', () => {
		const { subject, message } = renderEmail('NewVolunteer', args);
		expect(subject).not.toMatch(/\$\d/);
		expect(message).not.toMatch(/\$\d/);
	});
});

describe('optional notices', () => {
	// The registry decides what a scholar may silence, and the settings interface is
	// generated from it. A template marked optional with no label would render a control
	// with no words on it; a label with no template would be a setting for nothing.
	it('gives every silenceable notice a label on the scholar profile', () => {
		const labels = Object.keys(en.page.scholar.notifications.label).sort();
		expect([...OptionalEmails].sort()).toEqual(labels);
	});

	// Consequential mail is not a courtesy. Someone who has been charged, declined, or
	// assigned does not get to opt out of being told.
	it('leaves consequential mail with no opt-out', () => {
		for (const event of [
			'SubmissionCharged',
			'TransactionDeclined',
			'VerifyEmail',
			'WorkCompensated'
		])
			expect(OptionalEmails).not.toContain(event as EmailType);
		expect(Object.keys(Emails).length).toBeGreaterThan(OptionalEmails.length);
	});
});
