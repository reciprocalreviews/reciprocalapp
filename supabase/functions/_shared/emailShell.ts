// Shared, branded HTML shell for every email Reciprocal Reviews sends.
//
// This module is the single source of truth for the visual identity of
// *application* emails (the `resend` edge function and the `remind` cron job).
// It is intentionally pure and dependency-free so it runs unchanged in the Deno
// edge runtime. The static Supabase auth templates in `supabase/templates/`
// are hand-authored to mirror this same shell (auth emails are rendered by
// GoTrue, not this code), so keep the two visually in sync when editing.
//
// English only: we have no way to solicit a scholar's language preference yet.

/** Reciprocal Reviews brand colors, mirrored from src/app.html. */
const BRAND_COLOR = '#007284'; // --salient-color
const BRAND_COLOR_FADED = '#e1eff2'; // --salient-color-faded
const TEXT_COLOR = '#111111';
const MUTED_COLOR = '#888888'; // --inactive-color
const BORDER_COLOR = '#bbbbbb'; // --border-color

const WORDMARK = 'Reciprocal Reviews';
const FOOTER = 'This is an automated email sent by Reciprocal Reviews.';

/** Where the wordmark links when no origin is supplied. Declared here rather
 * than imported from templates.ts to keep this module dependency-free, as the
 * header above promises. */
const DEFAULT_ORIGIN = 'https://reciprocal.reviews';
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
 * Convert a plain/semi-HTML body into branded paragraph markup. The body is
 * split on blank lines into <p> blocks; bare https:// URLs become links. Any
 * inline tags the templates already embed (<a>, <strong>) pass through
 * untouched — interpolated argument values are escaped upstream in
 * src/email/templates.ts before they reach this code.
 */
export function paragraphsToHtml(body: string): string {
	return body
		.split(/\n{2,}/)
		.map((block) => block.trim())
		.filter((block) => block.length > 0)
		.map((block) => {
			// Auto-link bare URLs that aren't already inside an href attribute. The
			// URL stops short of trailing sentence punctuation: `[^\s<]+` is greedy,
			// so "visit https://x.com." used to link to "https://x.com." and 404.
			const linked = block.replace(
				/(^|[^"'>])(https?:\/\/[^\s<]*[^\s<.,;:!?)])/g,
				(_match, prefix, url) =>
					`${prefix}<a href="${url}" style="color: ${BRAND_COLOR};">${url}</a>`
			);
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
			.replace(/<\/(p|div|tr|h[1-6])>/gi, '\n\n')
			.replace(/<br\s*\/?>/gi, '\n')
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
	origin = DEFAULT_ORIGIN
}: {
	subject: string;
	bodyHtml: string;
	/** Where the wordmark links. Defaults to production so mail from a project
	 * that never configured `site_url` is unchanged. */
	origin?: string;
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
								${FOOTER}
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
	origin: string = DEFAULT_ORIGIN
): { html: string; text: string } {
	const html = wrapEmail({ subject, bodyHtml: paragraphsToHtml(body), origin });
	return { html, text: htmlToText(html) };
}
