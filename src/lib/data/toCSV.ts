/** Serialize a header row and data rows to CSV text.
 *
 * Every cell is quoted unconditionally and embedded quotes are doubled, which
 * is what makes commas, quotes and newlines inside a value safe. The inverse of
 * parseCSV, and tested against it as a round trip.
 *
 * Note this returns text, not a `data:` URI. Callers must hand it to the
 * browser as a Blob: the previous `encodeURI('data:text/csv,' + …)` approach
 * silently truncated every export at the first `#`, because encodeURI does not
 * escape it and the rest of the file was read as a fragment identifier — an
 * expertise of "C#" was enough to lose the remainder of the download. */
export default function toCSV(headers: string[], rows: string[][]): string {
	return [headers, ...rows].map((row) => row.map(quote).join(',')).join('\n');
}

function quote(value: string): string {
	return `"${value.replace(/"/g, '""')}"`;
}
