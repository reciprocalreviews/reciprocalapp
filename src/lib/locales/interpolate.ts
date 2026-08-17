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
 * user-visible string passes through, and it had no coverage at all. */
export default function interpolate(
	text: string | string[],
	shorthand: Record<string, string>,
	inputs: Record<string, string> = {}
): string {
	// An array is a sequence of paragraphs; join with blank lines so markdown
	// renders them as separate <p> blocks.
	const joined = Array.isArray(text) ? text.join('\n\n') : text;

	return joined
		.replace(/\$(\w+)/g, (_, key: string) => (key in shorthand ? shorthand[key] : `$${key}`))
		.replace(/\{(\w+)\}/g, (match, key: string) => (key in inputs ? inputs[key] : match));
}
