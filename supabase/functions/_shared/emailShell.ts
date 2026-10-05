// Shared, branded HTML shell for every email Reciprocal Reviews sends.
//
// This module is the single source of truth for the visual identity of
// *application* emails (the `resend` edge function and the `remind` cron job).
// It is intentionally pure and dependency-free so it runs unchanged in the Deno
// edge runtime. The static Supabase auth templates in `supabase/templates/`
// are hand-authored to mirror this same shell (auth emails are rendered by
// GoTrue, not this code), so keep the two visually in sync when editing.
//
// Exactly one thing varies between messages: the footer, which follows the Reply-To the
// message actually carries and the venue it is about, if any. See `footer` below.
//
// English only: we have no way to solicit a scholar's language preference yet.

/** Reciprocal Reviews brand colors, mirrored from src/app.html. */
const BRAND_COLOR = '#007284'; // --salient-color
const BRAND_COLOR_FADED = '#e1eff2'; // --salient-color-faded
const TEXT_COLOR = '#111111';
const MUTED_COLOR = '#888888'; // --inactive-color
const BORDER_COLOR = '#bbbbbb'; // --border-color

/**
 * The shared steward inbox — a Google Group in collaborative-inbox mode, so mail
 * sent here reaches every steward and can be assigned and resolved among them.
 * It is for the platform itself, not for the venues on it: it is the `Reply-To` on
 * email that is not about a venue (see the `resend` function and resolve_venue_reply_to
 * in supabase/schemas/emails.sql) and the address named on /contact.
 */
export const SUPPORT_EMAIL = 'stewards@reciprocal.reviews';

/**
 * The envelope sender. Mail comes *from* a robot but replies land somewhere
 * people share, hence the separate SUPPORT_EMAIL above. The display name matters:
 * without it clients show the bare address, which reads as no-reply automation.
 */
export const FROM_EMAIL = 'Reciprocal Reviews <notifications@reciprocal.reviews>';

/** Where defects and feature requests go. Named in every footer, because a bug report sent
 * to the steward inbox is one nobody else can see, follow, or add to. */
export const ISSUES_URL = 'https://github.com/reciprocalreviews/reciprocalapp/issues';

/** The venue a message is about: its short name (or its title, when it has none), which a
 * scholar chose and so is escaped here, and the absolute URL of its page, which lists the
 * people who run it. */
export type EmailVenue = { title: string; url: string };

const WORDMARK = 'Reciprocal Reviews';

function mailto(address: string): string {
	const escaped = escapeHtml(address);
	return `<a href="mailto:${escaped}" style="color: ${MUTED_COLOR};">${escaped}</a>`;
}

const SUPPORT_LINK = mailto(SUPPORT_EMAIL);
const ISSUES_CLAUSE = ` Report bugs or suggest features on <a href="${ISSUES_URL}" style="color: ${MUTED_COLOR};">GitHub</a>.`;

// Says who to talk to, not just who sent it, and what about. Every email is a potential
// support conversation, and this is the only place the recipient is told that replying
// works. It used to promise only that "a steward will see it", which was wrong twice over:
// the inbox reaches every steward, and people took it as an invitation to ask the stewards
// about the venues the platform hosts, which the stewards do not run.
const STEWARD_FOOTER = `Sent by Reciprocal Reviews. Replying to this email reaches all of the Reciprocal Reviews stewards at ${SUPPORT_LINK}, who help with the platform itself. Send questions about a journal or conference to its editors.${ISSUES_CLAUSE}`;

/**
 * The footer for a message about a venue. It names the venue and sends questions about it to
 * its editors, because a reader whose notice is about ACM TOCE reasonably assumes that
 * whoever sent it can answer for ACM TOCE.
 *
 * With a reply address, the reply already goes to the venue (resolve_venue_reply_to), or to
 * the editor who wrote the message. Without one -- no admin has a verified address -- a reply
 * falls back to the stewards, so the footer says that they can help only with the platform,
 * and points at the venue's page instead.
 */
function venueFooter(venue: EmailVenue, replyTo: string | undefined, copied: boolean): string {
	const title = escapeHtml(venue.title);
	// The venue's page is where its editors are listed, so "its editors" is the link.
	const editors = `<a href="${escapeHtml(venue.url)}" style="color: ${MUTED_COLOR};">its editors</a>`;
	const sent = `Sent by Reciprocal Reviews for ${title}.`;
	const route = replyTo
		? ` Replying to this email goes to ${mailto(replyTo)}${replyAllClause(copied)}. Send questions about ${title} to ${editors}, not the Reciprocal Reviews stewards; write ${SUPPORT_LINK} only for help with the platform itself.`
		: ` Send questions about ${title} to ${editors}. Replying to this email reaches all of the Reciprocal Reviews stewards at ${SUPPORT_LINK}, who can help with the platform itself but not with ${title}.`;
	return `${sent}${route}${ISSUES_CLAUSE}`;
}

function replyAllClause(copied: boolean): string {
	return copied ? ' — Reply All also reaches everyone copied on it' : '';
}

/**
 * The footer for a message that carries its OWN `Reply-To` and is not about a venue.
 *
 * The steward wording would be false here, and *quietly* false: the reader would believe a
 * reply had reached support when it had actually gone to a stranger. So name the real reply
 * address and keep SUPPORT_EMAIL visible as the separate route to help.
 *
 * `copied` decides whether Reply All is mentioned at all, on exactly the same reasoning. The
 * clause used to be unconditional, which was true of the only message that carried its own
 * Reply-To at the time -- the new-volunteer notice, addressed to one holder of the venue's top
 * role and copying the rest. It is false of a call for bids, which is N private copies on
 * purpose (its readers are reviewers who must not learn each other's addresses) and of a
 * new-volunteer notice sent to a venue with a single holder. Telling those readers that Reply
 * All reaches everyone copied invites them to answer a group that does not exist, and a footer
 * the reader would believe is worse than no footer at all.
 *
 * The address arrives as data and lands in an `href`, so it is escaped.
 */
function replyToFooter(replyTo: string, copied: boolean): string {
	return `Sent by Reciprocal Reviews. Replying to this email goes to ${mailto(replyTo)}${replyAllClause(copied)}. For help with the Reciprocal Reviews platform itself, write ${SUPPORT_LINK}.${ISSUES_CLAUSE}`;
}

/** Which footer a message gets. */
function footer(replyTo: string | undefined, copied: boolean, venue: EmailVenue | undefined) {
	if (venue) return venueFooter(venue, replyTo, copied);
	return replyTo ? replyToFooter(replyTo, copied) : STEWARD_FOOTER;
}

/** Where the wordmark links when no origin is supplied. Declared here rather
 * than imported from templates.ts to keep this module dependency-free, as the
 * header above promises. */
const DEFAULT_ORIGIN = 'https://reciprocal.reviews';

/**
 * The sentence an optional notice adds to its footer: where to turn it off. Only a notice a
 * scholar can silence carries it -- offering a way out of a charge or a verification would be
 * a link to a control that doesn't exist. The URL is built by `settingsUrlFor` in templates.ts
 * from trusted parts, and escaped here anyway because it lands in an `href`.
 */
function settingsFooter(settingsUrl: string): string {
	return ` You can turn off emails like this in your <a href="${escapeHtml(settingsUrl)}" style="color: ${MUTED_COLOR};">notification settings</a>.`;
}
const FONT_STACK =
	"'Quicksand', 'Josefin Sans', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif";

/** Escape a string for safe inclusion in HTML text/attribute content. */
export function escapeHtml(text: string): string {
	return text
		.replace(/&/g, '&amp;')
		.replace(/</g, '&lt;')
		.replace(/>/g, '&gt;')
		.replace(/"/g, '&quot;')
		.replace(/'/g, '&#39;');
}

/**
 * A call to action, as the whole of one block: `<rr-button href="https://…">Label</rr-button>`.
 *
 * Written as a pseudo-tag rather than a syntax like `[Label](url)` on purpose: it starts with
 * `<`, which `escapeArg` in templates.ts escapes in every argument, so only a template's own
 * text can produce one. A scholar-supplied title can never become a branded button.
 */
const BUTTON = /^<rr-button href="(https?:\/\/[^"\s]+)">([^<]+)<\/rr-button>$/;

/** A bulletproof button: a table cell carries the fill, because several clients ignore
 * padding and background on a bare `<a>`. */
function buttonHtml(href: string, label: string): string {
	return `<table role="presentation" cellpadding="0" cellspacing="0" style="margin: 0 0 24px 0;"><tr><td style="background-color: ${BRAND_COLOR}; border-radius: 6px;"><a href="${href}" style="display: inline-block; padding: 10px 20px; color: #ffffff; font-weight: 700; text-decoration: none; border-radius: 6px;">${label}</a></td></tr></table>`;
}

/** Every line of the block starts with "• ": a list, with real bullets and a hanging indent
 * so a wrapped title lines up under its first word rather than under the bullet. */
function isList(block: string): boolean {
	return block.split('\n').every((line) => line.startsWith('• '));
}

function listHtml(block: string): string {
	const items = block
		.split('\n')
		.map((line) => `<li style="margin: 0 0 6px 0; padding-left: 4px;">${line.slice(2)}</li>`)
		.join('');
	return `<ul style="margin: 0 0 16px 0; padding: 0 0 0 22px;">${items}</ul>`;
}

/**
 * Convert a plain/semi-HTML body into branded paragraph markup. The body is
 * split on blank lines into <p> blocks; bare https:// URLs become links. Any
 * inline tags the templates already embed (<a>, <strong>) pass through
 * untouched — interpolated argument values are escaped upstream in
 * src/email/templates.ts before they reach this code.
 *
 * Two kinds of block are not paragraphs: a list (every line starts with "• ") and a
 * button (see BUTTON).
 */
export function paragraphsToHtml(body: string): string {
	return body
		.split(/\n{2,}/)
		.map((block) => block.trim())
		.filter((block) => block.length > 0)
		.map((block) => {
			const button = block.match(BUTTON);
			if (button) return buttonHtml(button[1], button[2]);
			// Auto-link bare URLs that aren't already inside an href attribute. The
			// URL stops short of trailing sentence punctuation: `[^\s<]+` is greedy,
			// so "visit https://x.com." used to link to "https://x.com." and 404.
			const linked = block.replace(
				/(^|[^"'>])(https?:\/\/[^\s<]*[^\s<.,;:!?)])/g,
				(_match, prefix, url) =>
					`${prefix}<a href="${url}" style="color: ${BRAND_COLOR};">${url}</a>`
			);
			if (isList(block)) return listHtml(linked);
			// Preserve single newlines within a paragraph as line breaks.
			return `<p style="margin: 0 0 16px 0;">${linked.replace(/\n/g, '<br />')}</p>`;
		})
		.join('\n');
}

/** Derive a clean text/plain alternative from rendered HTML. */
export function htmlToText(html: string): string {
	return (
		html
			.replace(/<style[\s\S]*?<\/style>/gi, '')
			.replace(/<\/(p|div|tr|ul|h[1-6])>/gi, '\n\n')
			.replace(/<li[^>]*>/gi, '• ')
			.replace(/<\/li>/gi, '\n')
			.replace(/<br\s*\/?>/gi, '\n')
			// A web link whose text is not its own address would lose its destination once the
			// tags go, so it is kept beside the text: "notification settings (https://…)". Links
			// that ARE their address (auto-linked URLs) and mailto links read fine as they are.
			.replace(/<a\s[^>]*href="(https?:[^"]*)"[^>]*>([^<]*)<\/a>/gi, (_match, href, label) =>
				label === href ? label : `${label} (${href})`
			)
			.replace(/<[^>]+>/g, '')
			.replace(/&nbsp;/g, ' ')
			// The ampersand is decoded LAST, mirroring escapeHtml where it is escaped
			// first. Decoding it first turned "&amp;lt;" into "&lt;", which the next
			// pass decoded again into "<" — resurrecting markup that had been
			// deliberately escaped twice.
			.replace(/&lt;/g, '<')
			.replace(/&gt;/g, '>')
			.replace(/&quot;/g, '"')
			.replace(/&#39;/g, "'")
			.replace(/&amp;/g, '&')
			.replace(/\n{3,}/g, '\n\n')
			.split('\n')
			.map((line) => line.trim())
			.join('\n')
			.trim()
	);
}

/**
 * Wrap already-rendered body HTML in the branded, email-client-safe shell
 * (table layout, inline CSS, text wordmark header, footer). `bodyHtml` is
 * inserted as-is, so callers are responsible for escaping any untrusted values.
 */
export function wrapEmail({
	subject,
	bodyHtml,
	origin = DEFAULT_ORIGIN,
	replyTo,
	copied = false,
	settingsUrl,
	venue
}: {
	subject: string;
	bodyHtml: string;
	/** Where the wordmark links. Defaults to production so mail from a project
	 * that never configured `site_url` is unchanged. */
	origin?: string;
	/** The address this message's replies actually reach, when that is not the steward
	 * inbox. Changes the footer and nothing else — the `Reply-To` header itself is set by
	 * the caller that posts to Resend. Absent for every message that carries no override,
	 * which is nearly all of them. */
	replyTo?: string;
	/** Whether the message actually copies anyone, so the footer only offers Reply All when
	 * there is somebody for it to reach. */
	copied?: boolean;
	/** Where the recipient can silence this notice, for an optional one. Adds one sentence
	 * to the footer; absent for consequential mail. */
	settingsUrl?: string;
	/** The venue this message is about, if any, so the footer can name it and send questions
	 * about it to its editors rather than the stewards. */
	venue?: EmailVenue;
}): string {
	return `<!doctype html>
<html lang="en">
	<head>
		<meta charset="utf-8" />
		<meta name="viewport" content="width=device-width, initial-scale=1.0" />
		<meta name="color-scheme" content="light only" />
		<title>${escapeHtml(subject)}</title>
	</head>
	<body style="margin: 0; padding: 0; background-color: ${BRAND_COLOR_FADED};">
		<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color: ${BRAND_COLOR_FADED}; padding: 24px 0;">
			<tr>
				<td align="center">
					<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width: 560px; background-color: #ffffff; border: 1px solid ${BORDER_COLOR}; border-radius: 8px; overflow: hidden; font-family: ${FONT_STACK};">
						<tr>
							<td style="background-color: ${BRAND_COLOR}; padding: 20px 32px;">
								<a href="${escapeHtml(origin)}" style="color: #ffffff; font-size: 20px; font-weight: 700; text-decoration: none;">${WORDMARK}</a>
							</td>
						</tr>
						<tr>
							<td style="padding: 32px; color: ${TEXT_COLOR}; font-size: 15px; line-height: 1.5;">
${bodyHtml}
							</td>
						</tr>
						<tr>
							<td style="padding: 20px 32px; border-top: 1px solid ${BORDER_COLOR}; color: ${MUTED_COLOR}; font-size: 12px; line-height: 1.5;">
								${footer(replyTo, copied, venue)}${settingsUrl ? settingsFooter(settingsUrl) : ''}
							</td>
						</tr>
					</table>
				</td>
			</tr>
		</table>
	</body>
</html>`;
}

/**
 * Convenience helper: take a plain/semi-HTML message body and produce both the
 * branded HTML and a text/plain alternative ready to hand to Resend.
 */
export function renderBrandedEmail(
	subject: string,
	body: string,
	origin: string = DEFAULT_ORIGIN,
	// Trailing and optional: only a message that names its own Reply-To passes it, and
	// everything else replies to the stewards.
	replyTo?: string,
	// Also trailing and optional: only the consumer that knows the row's `cc` can answer this,
	// and every other caller sends to one recipient.
	copied: boolean = false,
	// Trailing and optional for the same reason: only a caller that knows the row's scholar
	// and event can say where that scholar turns it off. See `settingsUrlFor`.
	settingsUrl?: string,
	// Trailing and optional too: only the consumer that reads the row's venue can name it.
	venue?: EmailVenue
): { html: string; text: string } {
	const html = wrapEmail({
		subject,
		bodyHtml: paragraphsToHtml(body),
		origin,
		replyTo,
		copied,
		settingsUrl,
		venue
	});
	return { html, text: htmlToText(html) };
}
