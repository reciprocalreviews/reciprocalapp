/** Parse a CSV string with a header row into an array of records. Handles
 * double-quoted fields and escaped quotes (""). Does not support fields
 * containing newlines. */
export default function parseCSV(text: string): Record<string, string>[] {
	const lines = text
		.replace(/\r\n/g, '\n')
		.split('\n')
		.filter((line) => line.trim().length > 0);
	if (lines.length < 2) return [];

	const headers = parseRow(lines[0]).map((h) => h.trim());
	const rows: Record<string, string>[] = [];
	for (let i = 1; i < lines.length; i++) {
		const cells = parseRow(lines[i]);
		const row: Record<string, string> = {};
		for (let j = 0; j < headers.length; j++) {
			row[headers[j]] = (cells[j] ?? '').trim();
		}
		rows.push(row);
	}
	return rows;
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
