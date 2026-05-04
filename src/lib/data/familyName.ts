/** Heuristic: return the last whitespace-separated token of a person's full
 * name. Convention assumes the family name is the last word. Falls back to
 * the whole name (or empty string) if there's no space. Used for stable
 * alphabetical sorting of scholars. */
export default function familyName(name: string | null | undefined): string {
	const trimmed = (name ?? '').trim();
	const idx = trimmed.lastIndexOf(' ');
	return idx === -1 ? trimmed : trimmed.slice(idx + 1);
}
