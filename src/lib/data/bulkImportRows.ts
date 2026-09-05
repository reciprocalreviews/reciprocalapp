/** Row-level rules for the bulk submission importer: which rows are duplicates,
 * what is wrong with a row, how many tokens the import will need to mint, and
 * how a parsed CSV maps onto rows.
 *
 * Extracted from BulkImport.svelte because this is money-adjacent data ingest —
 * an import can create a whole conference's submissions and a mint sized to
 * their total cost — and none of it was reachable by a test. */

import type { ColumnMapping, RoleColumns } from './columnMapping';

/** The editable shape of one row in the import table. */
export type ImportRow = {
	title: string;
	externalID: string;
	expertise: string;
	submissionType: string;
	previousID: string;
	note: string;
	/** The name each role's column wrote on this row, keyed by role id, as the
	 * file wrote it. One key per role that has a column — present and empty when
	 * the cell is blank, so a field can be bound to it without meeting an
	 * `undefined`. */
	people: Record<string, string>;
};

/** Only the submission-type fields these rules read. */
export type ImportSubmissionType = { id: string; name: string; submission_cost: number };

/** Which submission type each distinct value in the file's type column becomes,
 * keyed by that value normalized (collapsed and lowercased).
 *
 * Resolution is decided once, for the whole import, where the editor can see it
 * and change it. It used to happen per row inside `rowsFromParsed`, which meant a
 * file whose type names matched nothing — the normal case, since a venue's type
 * names are its own — silently became a batch of the default type, and the
 * default type's cost silently set the mint. */
export type TypeAssignments = Record<string, string>;

/** The distinct values in the file's type column, with how many rows carry each,
 * most common first. Empty cells are not values and are left out. */
export function distinctTypeValues(
	parsed: Record<string, string>[],
	header: string | null
): { value: string; count: number }[] {
	if (header === null) return [];
	const counts = new Map<string, { value: string; count: number }>();
	for (const record of parsed) {
		const value = collapse(record[header] ?? '');
		if (value.length === 0) continue;
		const key = value.toLowerCase();
		const seen = counts.get(key);
		if (seen === undefined) counts.set(key, { value, count: 1 });
		else seen.count++;
	}
	return [...counts.values()].sort((a, b) => b.count - a.count);
}

/** Pre-fill each distinct value with the submission type of the same name, and
 * everything else with the default. Exactly the rule this module applied per row
 * before; the difference is that the result is now visible and changeable. */
export function guessTypeAssignments(
	values: { value: string }[],
	types: ImportSubmissionType[],
	defaultSubmissionType: string
): TypeAssignments {
	const assignments: TypeAssignments = {};
	for (const { value } of values) {
		const matched = types.find((t) => t.name.toLowerCase() === value.toLowerCase());
		assignments[value.toLowerCase()] = matched ? matched.id : defaultSubmissionType;
	}
	return assignments;
}

/** Why a row cannot be imported, as a stable key the component maps to locale
 * text. Ordered by which is reported first when several apply. */
export type RowProblem =
	'title' | 'externalID' | 'duplicateExisting' | 'duplicateRow' | 'personUnresolved';

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
	context: {
		existingExternalIDs: Set<string>;
		duplicates: Set<number>;
		/** Rows naming somebody the venue could not identify. Optional, since a
		 * caller that offers no person column has nobody to resolve. */
		personUnresolved?: Set<number>;
	}
): RowProblem | null {
	if (row.title.trim().length === 0) return 'title';
	if (row.externalID.trim().length === 0) return 'externalID';
	if (context.existingExternalIDs.has(row.externalID.trim())) return 'duplicateExisting';
	if (context.duplicates.has(index)) return 'duplicateRow';
	// Last, so the checks that were here first keep reporting first: a row missing
	// its title has a more basic problem than one whose editor could not be named.
	if (context.personUnresolved?.has(index)) return 'personUnresolved';
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

/** Collapse runs of whitespace — including the newlines a quoted field may
 * carry — into single spaces. Applied to the single-line fields, so a title that
 * wrapped across two lines in the export arrives as one line here rather than
 * putting a newline through a single-line text field and into the database. */
function collapse(value: string): string {
	return value.replace(/\s+/g, ' ').trim();
}

/** Read one field's cell out of a parsed record, or '' when the field is mapped
 * to nothing or the column is absent. */
function cell(record: Record<string, string>, header: string | null): string {
	return header === null ? '' : (record[header] ?? '');
}

/** Map parsed CSV records onto import rows, reading each field from whichever
 * column the editor matched to it.
 *
 * The importer does not require a CSV to use its own column names: `mapping` says
 * which header feeds which field and `roleColumns` which header names the holder
 * of which venue role, both chosen by the editor. `typeAssignments` says what each
 * distinct value in the type column becomes; a value with no assignment falls back
 * to the default, which is the case for a row typed in by hand. */
export function rowsFromParsed(
	parsed: Record<string, string>[],
	mapping: ColumnMapping,
	roleColumns: RoleColumns,
	defaultSubmissionType: string,
	typeAssignments: TypeAssignments = {}
): ImportRow[] {
	return parsed.map((record) => {
		const typeValue = collapse(cell(record, mapping.submissionType)).toLowerCase();
		return {
			title: collapse(cell(record, mapping.title)),
			externalID: collapse(cell(record, mapping.externalID)),
			expertise: collapse(cell(record, mapping.expertise)),
			submissionType: typeAssignments[typeValue] ?? defaultSubmissionType,
			previousID: collapse(cell(record, mapping.previousID)),
			// One key per role with a column, whether or not the cell has anything
			// in it. Names are collapsed like the other single-line fields, so a
			// name wrapped across two lines in the export never reaches name
			// matching with a newline inside it.
			people: Object.fromEntries(
				Object.entries(roleColumns).map(([role, header]) => [role, collapse(cell(record, header))])
			),
			// Not collapsed: a multi-line status or comment column is the note's
			// content, and flattening it would destroy what it says.
			note: cell(record, mapping.note).trim()
		};
	});
}
