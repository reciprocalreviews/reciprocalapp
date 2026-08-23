import { escapeHTML, isHtml, type Html } from './html';

/** The substitution pass every localized string in the app goes through.
 *
 * Two independent replacements, in order:
 *
 * 1. `$name` — a shorthand defined in the locale's `shorthand` table (the ✖ and
 *    ✓ glyphs, "Admin", "Minter", and so on), so a symbol can be changed in one
 *    place rather than in every string that shows it.
 * 2. `{name}` — a caller-supplied input, for the values only the call site knows.
 *
 * An unknown key is left exactly as written, `$name` or `{name}`. That is
 * deliberate: rendering the literal placeholder makes a missing string obvious
 * to whoever is looking at the page, whereas substituting an empty string or
 * `undefined` would silently produce a sentence with a hole in it. The same
 * discipline as renderEmail, which leaves an unmatched `$2` in place.
 *
 * Extracted from Text.svelte so it can be tested: it is the single point every
 * user-visible string passes through, and it had no coverage at all.
 *
 * ## Why `escape` exists
 *
 * When the result is bound for `{@html}` — which is every `<Text markdown>` —
 * an input is markup, not text. `venue.description` is written by a venue's
 * editors and substituted into `page.venue.paragraph.description`, so before
 * this parameter existed a description of `<img src=x onerror=…>` ran as script
 * for every visitor to that venue. Inputs are therefore escaped by default in
 * that mode, and a value that really is markup we generated has to say so by
 * arriving as `Html` (see ./html). Shorthand is not escaped: it is authored in
 * the locale file alongside the strings it appears in, and `$delete` is `✖`.
 *
 * In the plain-text mode Svelte escapes the interpolated result itself, so
 * escaping here too would double-encode and show the reader a literal `&lt;`.
 */
export default function interpolate(
	text: string | string[],
	shorthand: Record<string, string>,
	inputs: Record<string, string | Html> = {},
	escape = false
): string {
	// An array is a sequence of paragraphs; join with blank lines so markdown
	// renders them as separate <p> blocks.
	const joined = Array.isArray(text) ? text.join('\n\n') : text;

	return joined
		.replace(/\$(\w+)/g, (_, key: string) => (key in shorthand ? shorthand[key] : `$${key}`))
		.replace(/\{(\w+)\}/g, (match, key: string) => {
			if (!(key in inputs)) return match;
			const value = inputs[key];
			if (isHtml(value)) return value.html;
			return escape ? escapeHTML(value) : value;
		});
}
