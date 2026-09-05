/** A record whose cell count didn't match the header, reported so the caller can
 * warn rather than silently keep a misaligned record. `line` is 1-based and
 * counts the header, so it matches what a spreadsheet shows. When a record spans
 * several physical lines — a quoted field containing newlines — this is the line
 * the record *starts* on, which is where you go to fix it. */
export type RaggedRow = { line: number; cells: number; expected: number };

export type ParsedCSV = {
	rows: Record<string, string>[];
	/** Empty when every record had exactly as many cells as the header. */
	ragged: RaggedRow[];
};

/** One record of the file, with the physical line it began on. */
type CSVRecord = { cells: string[]; line: number };

/** Parse a CSV string with a header row into an array of records. Handles
 * double-quoted fields, escaped quotes (""), newlines inside quoted fields, a
 * leading byte order mark, and a header that ends in a trailing comma.
 *
 * Records whose cell count differs from the header are still returned — extra
 * cells are dropped and missing ones filled with '' — but they are also
 * reported in `ragged`. They were previously discarded in silence, so a single
 * unquoted comma in a title shifted every following column and dropped the last
 * field, and a bulk import landed with wrong external IDs and no warning.
 *
 * Scanning the whole text rather than splitting it into lines first is what
 * makes a newline inside a quoted field work. Real exports from reviewing
 * platforms wrap long titles and carry multi-line status fields, and splitting
 * on newlines shattered every one of those records into unusable fragments. */
export default function parseCSV(text: string): ParsedCSV {
	// Strip a leading byte order mark before anything reads the first header —
	// otherwise it stays glued to the front of that header's name, invisible in
	// every error message, and nothing matches it.
	const withoutBOM = text.charCodeAt(0) === 0xfeff ? text.slice(1) : text;

	// A CRLF inside a quoted field becomes a plain newline in the cell, which is
	// what a spreadsheet would show.
	const records = tokenize(withoutBOM.replace(/\r\n/g, '\n')).filter(
		// Blank lines are not records. A record of only commas still is, and still
		// reports as ragged.
		(record) => !(record.cells.length === 1 && record.cells[0].trim().length === 0)
	);
	if (records.length < 2) return { rows: [], ragged: [] };

	const rawHeaders = records[0].cells.map((h) => h.trim());

	// Exports commonly end their header row with a trailing comma, which would
	// otherwise make every data row ragged and add a nameless column. Forgive
	// exactly as many trailing empty headers as the header itself declares, and
	// only from the end: an empty header in the *middle* is real misalignment,
	// and dropping it would shift every column after it.
	const headers = rawHeaders.slice();
	while (headers.length > 0 && headers[headers.length - 1].length === 0) headers.pop();
	const droppedHeaders = rawHeaders.length - headers.length;
	if (headers.length === 0) return { rows: [], ragged: [] };

	const rows: Record<string, string>[] = [];
	const ragged: RaggedRow[] = [];
	for (let i = 1; i < records.length; i++) {
		let cells = records[i].cells;

		// Drop at most as many trailing empty cells as the header dropped, so a
		// data row that also ends in a comma lines up rather than reporting.
		let allowed = droppedHeaders;
		while (
			allowed > 0 &&
			cells.length > headers.length &&
			cells[cells.length - 1].trim().length === 0
		) {
			cells = cells.slice(0, -1);
			allowed--;
		}

		if (cells.length !== headers.length)
			ragged.push({ line: records[i].line, cells: cells.length, expected: headers.length });

		const row: Record<string, string> = {};
		for (let j = 0; j < headers.length; j++) {
			row[headers[j]] = (cells[j] ?? '').trim();
		}
		rows.push(row);
	}
	return { rows, ragged };
}

/** Scan the whole text into records, tracking the line each one began on.
 *
 * Quote handling is deliberately identical to what this module did per-line
 * before: a `"` outside a field opens it, `""` inside is a literal quote, a lone
 * `"` closes it, and anything after a closing quote keeps appending to the same
 * cell. Only newlines behave differently, and only inside quotes. */
function tokenize(text: string): CSVRecord[] {
	const records: CSVRecord[] = [];
	let cells: string[] = [];
	let current = '';
	let inQuotes = false;
	let line = 1;
	let recordLine = 1;

	for (let i = 0; i < text.length; i++) {
		const c = text[i];
		if (inQuotes) {
			if (c === '"') {
				if (text[i + 1] === '"') {
					current += '"';
					i++;
				} else {
					inQuotes = false;
				}
			} else {
				// The newline belongs to the cell, but the file still advanced a line.
				if (c === '\n') line++;
				current += c;
			}
		} else if (c === '"') {
			inQuotes = true;
		} else if (c === ',') {
			cells.push(current);
			current = '';
		} else if (c === '\n') {
			cells.push(current);
			records.push({ cells, line: recordLine });
			cells = [];
			current = '';
			line++;
			recordLine = line;
		} else {
			current += c;
		}
	}

	// The last record has no terminating newline. An unterminated quote closes
	// here too, so its content is kept rather than lost.
	cells.push(current);
	records.push({ cells, line: recordLine });
	return records;
}
