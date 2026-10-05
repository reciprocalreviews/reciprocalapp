import { describe, expect, it } from 'vitest';
import {
	escapeHtml,
	htmlToText,
	ISSUES_URL,
	paragraphsToHtml,
	renderBrandedEmail,
	SUPPORT_EMAIL
} from './emailShell';

describe('escapeHtml', () => {
	it('escapes the five characters that can break out of text or an attribute', () => {
		expect(escapeHtml(`<a href="x" title='y'>&`)).toBe(
			'&lt;a href=&quot;x&quot; title=&#39;y&#39;&gt;&amp;'
		);
	});

	// The ampersand must be escaped first, or the escapes it introduces would
	// themselves be re-escaped by the later passes.
	it('does not double-escape the entities it just introduced', () => {
		expect(escapeHtml('<')).toBe('&lt;');
		expect(escapeHtml('&lt;')).toBe('&amp;lt;');
	});
});

describe('paragraphsToHtml', () => {
	it('splits blank-line-separated blocks into paragraphs', () => {
		const html = paragraphsToHtml('One.\n\nTwo.');
		expect(html.match(/<p /g)).toHaveLength(2);
		expect(html).toContain('One.');
		expect(html).toContain('Two.');
	});

	it('preserves single newlines inside a paragraph as line breaks', () => {
		expect(paragraphsToHtml('One.\nStill one.')).toContain('<br />');
	});

	it('auto-links a bare URL', () => {
		expect(paragraphsToHtml('See https://example.com now')).toContain(
			'<a href="https://example.com"'
		);
	});

	// The URL pattern is greedy up to whitespace, so sentence punctuation used to
	// be captured into the href and the link resolved to a 404.
	it('leaves sentence punctuation out of the link', () => {
		const html = paragraphsToHtml('Visit https://example.com.');
		expect(html).toContain('href="https://example.com"');
		expect(html).not.toContain('href="https://example.com."');
	});

	it('leaves a trailing comma or closing paren out of the link', () => {
		expect(paragraphsToHtml('Visit https://example.com, then leave.')).toContain(
			'href="https://example.com"'
		);
		expect(paragraphsToHtml('(see https://example.com)')).toContain('href="https://example.com"');
	});

	it('does not re-link a URL already inside an href', () => {
		const html = paragraphsToHtml('<a href="https://example.com">x</a>');
		expect(html.match(/<a /g)).toHaveLength(1);
	});
});

describe('htmlToText', () => {
	it('strips tags and turns block ends into blank lines', () => {
		expect(htmlToText('<p>One.</p><p>Two.</p>')).toBe('One.\n\nTwo.');
	});

	it('turns <br> into a single newline', () => {
		expect(htmlToText('<p>One.<br />Two.</p>')).toBe('One.\nTwo.');
	});

	it('drops style blocks entirely', () => {
		expect(htmlToText('<style>p { color: red }</style><p>Hi.</p>')).toBe('Hi.');
	});

	it('decodes the entities escapeHtml produces', () => {
		expect(htmlToText('<p>&lt;b&gt; &amp; &quot;q&quot; &#39;a&#39;</p>')).toBe('<b> & "q" \'a\'');
	});

	// Decoding &amp; first turned "&amp;lt;" into "&lt;", which the next pass then
	// decoded again into "<" — resurrecting markup that had been deliberately
	// escaped twice. The ampersand pass has to run last, mirroring escapeHtml,
	// where it runs first.
	it('does not double-decode an escaped entity', () => {
		expect(htmlToText('<p>&amp;lt;b&amp;gt;</p>')).toBe('&lt;b&gt;');
	});

	it('round-trips escaped text without resurrecting it as markup', () => {
		const escapedTwice = escapeHtml(escapeHtml('<script>'));
		expect(htmlToText(`<p>${escapedTwice}</p>`)).toBe('&lt;script&gt;');
	});
});

describe('renderBrandedEmail', () => {
	// The footer is the only place a recipient is told that replying reaches a
	// person. Losing it would silently turn every notification back into a
	// dead end, and nothing else in the pipeline would fail.
	it('names the steward inbox in the HTML footer', () => {
		const { html } = renderBrandedEmail('Subject', 'Body.');
		expect(html).toContain(`mailto:${SUPPORT_EMAIL}`);
		expect(html).toContain(SUPPORT_EMAIL);
	});

	// The text/plain alternative is derived by stripping tags, so an address that
	// lived only in an href attribute would vanish for plain-text readers.
	it('keeps the steward inbox readable in the text alternative', () => {
		const { text } = renderBrandedEmail('Subject', 'Body.');
		expect(text).toContain(SUPPORT_EMAIL);
	});

	it('still renders the body it was given', () => {
		const { html, text } = renderBrandedEmail('Subject', 'Hello there.');
		expect(html).toContain('Hello there.');
		expect(text).toContain('Hello there.');
	});

	// A message that carries its own Reply-To must not repeat the steward promise. It
	// would be false, and *quietly* false: the reader would believe a reply had reached
	// support when it had actually gone to a stranger.
	it('names the real reply address when the message carries its own', () => {
		const { html } = renderBrandedEmail('Subject', 'Body.', undefined, 'newbie@uni.edu');
		expect(html).toContain('mailto:newbie@uni.edu');
		expect(html).not.toContain('reaches all of the Reciprocal Reviews stewards');
	});

	// Support has to stay reachable. The reply goes to a person; a question about the
	// platform itself still belongs with the stewards, so both addresses appear.
	it('still names the steward inbox as the route to support', () => {
		const { html } = renderBrandedEmail('Subject', 'Body.', undefined, 'newbie@uni.edu');
		expect(html).toContain(SUPPORT_EMAIL);
	});

	// Both addresses live only in href attributes, which htmlToText strips.
	it('keeps both addresses readable in the text alternative', () => {
		const { text } = renderBrandedEmail('Subject', 'Body.', undefined, 'newbie@uni.edu');
		expect(text).toContain('newbie@uni.edu');
		expect(text).toContain(SUPPORT_EMAIL);
	});

	// Reply All is offered only when somebody is actually copied. The clause used to be
	// unconditional, which was true of the only message that carried its own Reply-To at the
	// time — the new-volunteer notice, addressed to one holder of a venue's top role and
	// copying the rest. It is false of a call for bids, which is N private copies on purpose,
	// and of a new-volunteer notice at a venue with a single holder.
	it('offers Reply All only when the message copies somebody', () => {
		const { html } = renderBrandedEmail('Subject', 'Body.', undefined, 'newbie@uni.edu', true);
		expect(html).toContain('Reply All');
	});

	it('does not invite Reply All on a message with no copies', () => {
		// The same argument as the steward promise above: a footer the reader would believe,
		// pointing at a group that does not exist, is worse than no footer at all.
		const { html } = renderBrandedEmail('Subject', 'Body.', undefined, 'newbie@uni.edu');
		expect(html).not.toContain('Reply All');
		expect(html).toContain('mailto:newbie@uni.edu');
	});

	it('falls back to the steward footer when there is no reply address', () => {
		// A volunteer with no verified contact address leaves reply_to null, and the
		// footer has to be correct for that case too.
		const { html } = renderBrandedEmail('Subject', 'Body.', undefined, undefined);
		expect(html).toContain('reaches all of the Reciprocal Reviews stewards');
	});

	// The stewards are for the platform, not for the venues on it. The footer used to promise
	// only that "a steward will see it", and people wrote to the stewards with questions about
	// a journal that only its editors could answer.
	it('says the stewards help with the platform, not with venues', () => {
		const { text } = renderBrandedEmail('Subject', 'Body.');
		expect(text).toContain('reaches all of the Reciprocal Reviews stewards');
		expect(text).toContain('help with the platform itself');
		expect(text).toContain('Send questions about a journal or conference to its editors');
	});

	// A bug report sent to the steward inbox is one nobody else can see or follow.
	it('sends bugs and feature requests to GitHub in every footer', () => {
		const venue = { title: 'ACM TOCE', url: 'https://reciprocal.reviews/venue/toce' };
		for (const { html } of [
			renderBrandedEmail('Subject', 'Body.'),
			renderBrandedEmail('Subject', 'Body.', undefined, 'newbie@uni.edu'),
			renderBrandedEmail('Subject', 'Body.', undefined, 'editor@uni.edu', false, undefined, venue),
			renderBrandedEmail('Subject', 'Body.', undefined, undefined, false, undefined, venue)
		])
			expect(html).toContain(`href="${ISSUES_URL}"`);
	});

	describe('for a message about a venue', () => {
		const venue = { title: 'ACM TOCE', url: 'https://reciprocal.reviews/venue/toce' };

		// A reader whose notice is about a journal assumes whoever sent it can answer for the
		// journal, so the footer names it and says where its questions go.
		it('names the venue and sends its questions to its editors', () => {
			const { text } = renderBrandedEmail(
				'Subject',
				'Body.',
				undefined,
				'editor@uni.edu',
				false,
				undefined,
				venue
			);
			expect(text).toContain('Sent by Reciprocal Reviews for ACM TOCE.');
			expect(text).toContain('Replying to this email goes to editor@uni.edu');
			expect(text).toContain(`Send questions about ACM TOCE to its editors (${venue.url})`);
			expect(text).toContain('not the Reciprocal Reviews stewards');
			// Still reachable, for a question about the platform itself.
			expect(text).toContain(SUPPORT_EMAIL);
		});

		// No admin has a verified address, so a reply falls back to the stewards. The footer
		// has to say so, and that they cannot help with the venue.
		it('admits a reply reaches the stewards when the venue has no address', () => {
			const { text } = renderBrandedEmail(
				'Subject',
				'Body.',
				undefined,
				undefined,
				false,
				undefined,
				venue
			);
			expect(text).toContain(`reaches all of the Reciprocal Reviews stewards at ${SUPPORT_EMAIL}`);
			expect(text).toContain('but not with ACM TOCE');
			expect(text).toContain(`Send questions about ACM TOCE to its editors (${venue.url})`);
		});

		// A venue's title is chosen by a scholar and lands in markup.
		it('escapes the venue title', () => {
			const { html } = renderBrandedEmail(
				'Subject',
				'Body.',
				undefined,
				undefined,
				false,
				undefined,
				{ title: '<b>Evil</b>', url: venue.url }
			);
			expect(html).not.toContain('<b>Evil</b>');
			expect(html).toContain('&lt;b&gt;Evil&lt;/b&gt;');
		});
	});

	// The address reaches the shell as data and lands inside an href, so a value carrying
	// a quote must not be able to close the attribute and add one of its own.
	it('escapes the reply address rather than letting it break out of the href', () => {
		const { html } = renderBrandedEmail(
			'Subject',
			'Body.',
			undefined,
			'evil@x.com" onclick="alert(1)'
		);
		expect(html).not.toContain('onclick="alert(1)"');
		expect(html).toContain('&quot;');
	});
});
