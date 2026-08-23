/** Values that are already HTML, and are trusted to be.
 *
 * `interpolate` escapes every input it substitutes into a string bound for
 * `{@html}` — see the comment there for why. That default is what makes the
 * substitution safe, but a few values genuinely are markup we generated
 * ourselves (the token chip). Wrapping one in `html()` is how a caller says so,
 * and the wrapper is deliberately unpleasant to construct by accident: a bare
 * string can never satisfy it, so no call site can opt out of escaping without
 * naming this function, and every place that does is one `grep` away. */
export type Html = { readonly html: string };

/** Mark a string as trusted markup, exempting it from escaping.
 *
 * Only ever call this on markup this codebase built. Never on a value that
 * originated with a scholar, a venue, or a request. */
export function html(markup: string): Html {
	return { html: markup };
}

export function isHtml(value: string | Html): value is Html {
	return typeof value !== 'string';
}

/** Neutralize the characters that would let a value introduce markup of its own. */
export function escapeHTML(text: string): string {
	return text
		.replace(/&/g, '&amp;')
		.replace(/</g, '&lt;')
		.replace(/>/g, '&gt;')
		.replace(/"/g, '&quot;')
		.replace(/'/g, '&#39;');
}
