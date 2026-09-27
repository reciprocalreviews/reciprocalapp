import { describe, expect, test } from 'vitest';
// Ranking, matching, the cap and the fingerprint are decided in SQL and tested in
// supabase/tests/rpc/bidding_digest.sql. What is tested here is how a digest renders.
import { HostileDigest, ReeseDigest, TwoVenueDigest, totalOf } from './biddingDigest.fixtures';
import { renderEmail, settingsUrlFor, type BiddingDigestPayload } from './templates';
import { htmlToText, renderBrandedEmail } from './emailShell';
import { expertiseKey, expertiseTags } from '../lib/data/expertise';

const ORIGIN = 'https://rr.test';

function render(payload: BiddingDigestPayload) {
	const total = totalOf(payload);
	const { subject, message } = renderEmail(
		'BiddingDigest',
		[JSON.stringify(payload), `${total} submission${total === 1 ? '' : 's'}`],
		ORIGIN
	);
	return { subject, message, ...renderBrandedEmail(subject, message, ORIGIN) };
}

describe('expertiseTags', () => {
	// The same cases supabase/tests/rpc/bidding_digest.sql puts to private.expertise_keys, so
	// the roster's chips and the digest's matches follow one rule.
	test('splits on commas, trims, and drops empties', () => {
		expect(expertiseTags(' Peer Review ,, statistics ,')).toEqual(['Peer Review', 'statistics']);
		expect(expertiseTags(null)).toEqual([]);
		expect(expertiseTags('')).toEqual([]);
	});
	test('matches without regard to case', () => {
		expect(expertiseKey('Peer Review')).toBe(expertiseKey('peer review'));
	});
});

describe('BiddingDigest template', () => {
	test('lists each submission with what it matched, and links to bidding', () => {
		const { subject, text } = render(ReeseDigest);
		expect(subject).toBe('7 submissions open for bids in roles you volunteer for');
		expect(text).toContain('ToK · Reviewer');
		expect(text).toContain(
			'• A Study on the Effectiveness of Peer Review Incentives in Academic Publishing (matches peer review)'
		);
		expect(text).toContain('• Retraction Notices as a Genre\n');
		expect(text).not.toContain('needs');
		expect(text).toContain('Bid at ToK (https://rr.test/venue/knowledge/submissions)');
	});
	test('renders the list as a list and the link as a button', () => {
		const { html } = render(ReeseDigest);
		expect(html.match(/<li /g)).toHaveLength(7);
		expect(html).toMatch(
			/<td style="background-color: #007284;[^"]*"><a href="https:\/\/rr.test\/venue\/knowledge\/submissions"/
		);
	});
	test('gives each venue its own list and button, and counts what the cap left out', () => {
		const { text } = render(TwoVenueDigest);
		expect(text).toContain('…and 7 more on the bidding page.');
		expect(text.indexOf('Annals of Doubt · Referee')).toBeLessThan(text.indexOf('ToK · Reviewer'));
		expect(text).toContain('Bid at Annals of Doubt (https://rr.test/venue/doubt/submissions)');
	});
	test('renders scholar-supplied strings inert', () => {
		const { html } = render(HostileDigest);
		expect(html).not.toContain('<script>');
		expect(html).not.toContain('<b>Bold</b>');
		expect(html).toContain('https[:]//evil.example');
		expect(html).not.toMatch(/href="https:\/\/evil/);
		expect(html).toContain('&lt;i&gt;markup&lt;/i&gt;');
	});
	test('cannot be made to draw a button or split the list from a title', () => {
		const forged: BiddingDigestPayload = {
			groups: [
				{
					...HostileDigest.groups[0],
					items: [
						{
							title: '<rr-button href="https://evil.example">Pay</rr-button>\n• injected',
							matches: []
						}
					]
				}
			]
		};
		const { html } = render(forged);
		expect(html).not.toContain('evil.example"');
		expect(html.match(/<li /g)).toHaveLength(1);
		expect(
			html.match(
				/<table role="presentation" cellpadding="0" cellspacing="0" style="margin: 0 0 24px/g
			)
		).toHaveLength(1);
	});
	test('names a nameless venue and role, and an untitled submission, plainly', () => {
		const blank: BiddingDigestPayload = {
			groups: [
				{ ...ReeseDigest.groups[0], venue: ' ', role: '', items: [{ title: '', matches: [] }] }
			]
		};
		const { text } = render(blank);
		expect(text).toContain('Bid at this venue (https://rr.test/venue/knowledge/submissions)');
		expect(text).toContain('• Untitled submission');
		expect(text).not.toContain(' · ');
	});
	test('refuses a malformed payload rather than half-rendering it', () => {
		const good = ReeseDigest.groups[0];
		const bad = (payload: unknown) => () =>
			renderEmail('BiddingDigest', [JSON.stringify(payload), 'x'], ORIGIN);
		expect(bad({ groups: [] })).toThrow();
		expect(bad({ groups: [{ ...good, path: '../admin' }] })).toThrow();
		expect(bad({ groups: [{ ...good, more: 1.5 }] })).toThrow();
		expect(bad({ groups: [{ ...good, items: [{ title: 'x' }] }] })).toThrow();
		expect(() => renderEmail('BiddingDigest', ['not json', 'x'], ORIGIN)).toThrow();
	});
});

describe('settingsUrlFor', () => {
	const scholar = '7ff8621a-cbe0-4789-bbee-f008d38c4ac8';
	test('points an optional notice at its section, through login', () => {
		expect(settingsUrlFor('BiddingDigest', scholar, ORIGIN)).toBe(
			`${ORIGIN}/login?next=${encodeURIComponent(`/scholar/${scholar}#notifications-reviewing`)}`
		);
	});
	test('uses the section of the preference that actually silences it', () => {
		// SubmissionNeedsEditor is silenced by SubmissionsNeedEditors, a venues control.
		expect(settingsUrlFor('SubmissionNeedsEditor', scholar, ORIGIN)).toContain(
			encodeURIComponent('#notifications-venues')
		);
	});
	test('offers nothing for consequential mail or mail with no scholar', () => {
		expect(settingsUrlFor('AssignmentApproved', scholar, ORIGIN)).toBeUndefined();
		expect(settingsUrlFor('NewBid', null, ORIGIN)).toBeUndefined();
		expect(settingsUrlFor('NotATemplate', scholar, ORIGIN)).toBeUndefined();
	});
	test('keeps the link in the plain-text alternative', () => {
		const url = settingsUrlFor('NewBid', scholar, ORIGIN)!;
		const { text } = renderBrandedEmail('s', 'body', ORIGIN, undefined, false, url);
		expect(text).toContain(`notification settings (${url})`);
		expect(htmlToText('<a href="https://x.test">https://x.test</a>')).toBe('https://x.test');
	});
});
