/** A row whose cell count didn't match the header, reported so the caller can
 * warn rather than silently keep a misaligned record. `line` is 1-based and
 * counts the header, so it matches what a spreadsheet shows. */
export type RaggedRow = { line: number; cells: number; expected: number };

export type ParsedCSV = {
	rows: Record<string, string>[];
	/** Empty when every row had exactly as many cells as the header. */
	ragged: RaggedRow[];
};

/** Parse a CSV string with a header row into an array of records. Handles
 * double-quoted fields and escaped quotes (""). Does not support fields
 * containing newlines.
 *
 * Rows whose cell count differs from the header are still returned — extra
 * cells are dropped and missing ones filled with '' — but they are also
 * reported in `ragged`. They were previously discarded in silence, so a single
 * unquoted comma in a title shifted every following column and dropped the last
 * field, and a bulk import landed with wrong external IDs and no warning. */
export default function parseCSV(text: string): ParsedCSV {
	const lines = text
		.replace(/\r\n/g, '\n')
		.split('\n')
		.filter((line) => line.trim().length > 0);
	if (lines.length < 2) return { rows: [], ragged: [] };

	const headers = parseRow(lines[0]).map((h) => h.trim());
	const rows: Record<string, string>[] = [];
	const ragged: RaggedRow[] = [];
	for (let i = 1; i < lines.length; i++) {
		const cells = parseRow(lines[i]);
		if (cells.length !== headers.length)
			ragged.push({ line: i + 1, cells: cells.length, expected: headers.length });
		const row: Record<string, string> = {};
		for (let j = 0; j < headers.length; j++) {
			row[headers[j]] = (cells[j] ?? '').trim();
		}
		rows.push(row);
	}
	return { rows, ragged };
}

function parseRow(line: string): string[] {
	const cells: string[] = [];
	let current = '';
	let inQuotes = false;
	for (let i = 0; i < line.length; i++) {
		const c = line[i];
		if (inQuotes) {
			if (c === '"') {
				if (line[i + 1] === '"') {
					current += '"';
					i++;
				} else {
					inQuotes = false;
				}
			} else {
				current += c;
			}
		} else if (c === '"') {
			inQuotes = true;
		} else if (c === ',') {
			cells.push(current);
			current = '';
		} else {
			current += c;
		}
	}
	cells.push(current);
	return cells;
}
