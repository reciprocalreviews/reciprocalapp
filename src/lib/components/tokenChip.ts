import type LocaleText from '$lib/locales/Locale';
import { escapeHTML, html, type Html } from '$lib/locales/html';
import { TokenLabel } from './Labels';

/** The token chip as markup, for use inside a localized sentence.
 *
 * Tokens.svelte renders the same chip as a component, which is right in a table
 * cell or a list. It cannot help in prose: a sentence like "priced in review
 * tokens (e.g. ★ 10 tokens)" is one sentence, and `<Text>` renders a string, so
 * there is nowhere to put a component inside it. Hence a second rendering of the
 * same thing. The duplication is the point of the shared class names — the rules
 * live once, in the global block in src/app.html, because Svelte's scoped styles
 * never reach `{@html}` content. Change one of these two and change the other.
 *
 * Returns `Html`, which is what exempts it from the escaping `interpolate` does
 * to every other input.
 */
export default function tokenChip(
	tokens: LocaleText['widget']['tokens'],
	amount: number,
	options: { currency?: string; debit?: boolean } = {}
): Html {
	const { currency, debit = false } = options;
	const unit = amount === 1 ? tokens.single : tokens.plural;
	const name =
		currency === undefined
			? ''
			: ` <span class="currency">${escapeMarkdown(escapeHTML(currency))}</span>`;

	return html(
		`<span class="token${debit ? ' debit' : ''}">` +
			`<span class="star">${TokenLabel}</span> ${amount}${name} ${unit}` +
			`</span>`
	);
}

/** A currency name is venue-authored, and the chip is handed to `marked`, which
 * still parses markdown *inside* an inline element. Without this, a currency
 * called `*Kudos*` would come out italicized — and `[x](y)` would come out a
 * link. Escaping the HTML is what keeps the name from becoming markup; this is
 * what keeps it from becoming formatting. */
function escapeMarkdown(text: string): string {
	return text.replace(/([\\`*_[\]()<>#+\-!])/g, '\\$1');
}
