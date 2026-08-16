/** Row-level rules for the bulk submission importer: which rows are duplicates,
 * what is wrong with a row, how many tokens the import will need to mint, and
 * how a parsed CSV maps onto rows.
 *
 * Extracted from BulkImport.svelte because this is money-adjacent data ingest —
 * an import can create a whole conference's submissions and a mint sized to
 * their total cost — and none of it was reachable by a test. */

/** The editable shape of one row in the import table. */
export type ImportRow = {
	title: string;
	externalID: string;
	expertise: string;
	submissionType: string;
	previousID: string;
	note: string;
};

/** Only the submission-type fields these rules read. */
export type ImportSubmissionType = { id: string; name: string; submission_cost: number };

/** Why a row cannot be imported, as a stable key the component maps to locale
 * text. Ordered by which is reported first when several apply. */
export type RowProblem = 'title' | 'externalID' | 'duplicateExisting' | 'duplicateRow';

/** Indices of rows whose external ID collides with another row in the batch.
 * Blank IDs are skipped — they are already reported as a missing external ID,
 * and treating every blank row as a duplicate of every other would bury that. */
export function duplicateAcrossRows(rows: ImportRow[]): Set<number> {
	const seen = new Map<string, number[]>();
	rows.forEach((r, i) => {
		const id = r.externalID.trim();
		if (id.length === 0) return;
		if (!seen.has(id)) seen.set(id, []);
		seen.get(id)!.push(i);
	});
	const dupes = new Set<number>();
	for (const indices of seen.values()) {
		if (indices.length > 1) indices.forEach((i) => dupes.add(i));
	}
	return dupes;
}

/** The first problem with a row, or null if it is importable. */
export function rowError(
	row: ImportRow,
	index: number,
	context: { existingExternalIDs: Set<string>; duplicates: Set<number> }
): RowProblem | null {
	if (row.title.trim().length === 0) return 'title';
	if (row.externalID.trim().length === 0) return 'externalID';
	if (context.existingExternalIDs.has(row.externalID.trim())) return 'duplicateExisting';
	if (context.duplicates.has(index)) return 'duplicateRow';
	return null;
}

/** Total tokens the import will mint: the sum of each row's submission type cost.
 *
 * A row naming an unknown type contributes 0. That is a deliberate fallback and
 * a quiet one — it under-mints rather than failing — so it is pinned by a test.
 * In practice the type always comes from the venue's own list. */
export function mintAmount(rows: ImportRow[], types: ImportSubmissionType[]): number {
	return rows.reduce(
		(sum, r) => sum + (types.find((t) => t.id === r.submissionType)?.submission_cost ?? 0),
		0
	);
}

/** Map parsed CSV records onto import rows.
 *
 * Header spellings are accepted in both the lowercase form a spreadsheet tends
 * to produce and the camelCase form the table uses, since editors export from
 * many different reviewing platforms. An unrecognized submission type name falls
 * back to the chosen default rather than failing the row. */
export function rowsFromParsed(
	parsed: Record<string, string>[],
	types: ImportSubmissionType[],
	defaultSubmissionType: string
): ImportRow[] {
	return parsed.map((p) => {
		const typeName = (p.submission_type ?? '').trim().toLowerCase();
		const matched = typeName ? types.find((t) => t.name.toLowerCase() === typeName) : null;
		return {
			title: p.title ?? '',
			externalID: p.externalid ?? p.externalID ?? '',
			expertise: p.expertise ?? '',
			submissionType: matched ? matched.id : defaultSubmissionType,
			previousID: p.previousid ?? p.previousID ?? '',
			note: p.note ?? ''
		};
	});
}
