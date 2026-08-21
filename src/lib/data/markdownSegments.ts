/** A minimal inline-markdown tokenizer for changelog entries on the updates
 * page. Deliberately not a full markdown parser: it recognizes exactly the five
 * things CHANGELOG.md uses, so the page can render issue references as links to
 * GitHub and everything else as plain markup.
 *
 * Extracted from updates/+page.svelte because it is a hand-rolled scanner over
 * one alternation with six capture groups and a manual cursor — the shape of
 * code that quietly drops a character at a boundary. */

export type Segment =
	| string
	| { type: 'issue' | 'code' | 'bold' | 'italic'; text: string }
	| { type: 'link'; text: string; link: string };

/** `(#123)` issue refs, `` `code` ``, `**bold**`, `*italic*`, `[text](url)`.
 * Anything between matches is emitted verbatim as a string segment. */
const PATTERN = /\(#([0-9]+)\)|`([^`]+)`|\*\*([^*]+)\*\*|\*([^*]+)\*|\[([^\]]+)\]\(([^)]+)\)/g;

export default function markdownToSegments(text: string): Segment[] {
	const segments: Segment[] = [];
	let currentIndex = 0;
	// A fresh regex per call: PATTERN is global and carries lastIndex, so sharing
	// one instance across calls would make each call depend on the last.
	const regex = new RegExp(PATTERN.source, 'g');
	let match: RegExpExecArray | null;

	while ((match = regex.exec(text)) !== null) {
		if (match.index > currentIndex) {
			segments.push(text.substring(currentIndex, match.index));
		}
		if (match[1]) {
			segments.push({ type: 'issue', text: match[1] });
		} else if (match[2]) {
			segments.push({ type: 'code', text: match[2] });
		} else if (match[3]) {
			segments.push({ type: 'bold', text: match[3] });
		} else if (match[4]) {
			segments.push({ type: 'italic', text: match[4] });
		} else if (match[6]) {
			segments.push({ type: 'link', link: match[6], text: match[5] });
		}
		currentIndex = regex.lastIndex;
	}

	if (currentIndex < text.length) {
		segments.push(text.substring(currentIndex));
	}

	return segments;
}
