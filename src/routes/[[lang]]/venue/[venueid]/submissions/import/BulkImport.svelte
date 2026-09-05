<!-- svelte-ignore state_referenced_locally -->
<script lang="ts">
	import { goto } from '$app/navigation';
	import { venuePath } from '$lib/data/venuePath';
	import type { RoleRow, SubmissionType, SubmissionTypeID, VenueRow } from '$data/types';
	import Button from '$lib/components/Button.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import FileInput from '$lib/components/FileInput.svelte';
	import Form from '$lib/components/Form.svelte';
	import Note from '$lib/components/Note.svelte';
	import Options from '$lib/components/Options.svelte';
	import Paragraph from '$lib/components/Paragraph.svelte';
	import ScholarLink from '$lib/components/ScholarLink.svelte';
	import Table from '$lib/components/Table.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import { getDB } from '$lib/data/CRUD';
	import type { VenueCommitment } from '$lib/data/SupabaseCRUD.svelte';
	import {
		duplicateAcrossRows,
		mintAmount as mintTotal,
		rowError as rowProblem,
		rowsFromParsed
	} from '$lib/data/bulkImportRows';
	import {
		guessMapping,
		unmappedHeaders,
		type ColumnMapping,
		type ImportField
	} from '$lib/data/columnMapping';
	import { matchPersonName, type Candidate } from '$lib/data/matchPersonName';
	import parseCSV from '$lib/data/parseCSV';
	import type LocaleText from '$lib/locales/Locale';
	import Text from '$lib/locales/Text.svelte';
	import { getLocaleContext } from '$routes/Contexts';
	import { handle } from '$routes/feedback.svelte';

	let {
		venue,
		submissionTypes,
		existingExternalIDs,
		roles,
		commitments
	}: {
		venue: VenueRow;
		submissionTypes: SubmissionType[];
		existingExternalIDs: string[];
		roles: RoleRow[];
		commitments: VenueCommitment[];
	} = $props();

	const db = getDB();
	const locale = getLocaleContext();

	type Row = {
		title: string;
		externalID: string;
		expertise: string;
		submissionType: SubmissionTypeID;
		previousID: string;
		note: string;
		/** The name as the file wrote it, editable here. */
		person: string;
		/** A scholar the editor picked when the name alone was ambiguous. Kept
		 * separate from `person` so the text stays the file's and the choice stays
		 * revocable. */
		personChoice: string | null;
	};

	function emptyRow(): Row {
		return {
			title: '',
			externalID: '',
			expertise: '',
			submissionType: defaultSubmissionType,
			previousID: '',
			note: '',
			person: '',
			personChoice: null
		};
	}

	/** The fields this form offers a column for. Kept explicit so `guessMapping`
	 * does not claim a header for a field the editor was never shown — that
	 * header would then vanish from the ignored-columns note while feeding
	 * nothing. */
	const MappedFields: ImportField[] = [
		'title',
		'externalID',
		'expertise',
		'submissionType',
		'previousID',
		'note',
		'person'
	];

	function noMapping(): ColumnMapping {
		return {
			title: null,
			externalID: null,
			expertise: null,
			submissionType: null,
			previousID: null,
			note: null,
			person: null
		};
	}

	let defaultSubmissionType = $state<SubmissionTypeID>(submissionTypes[0].id);
	let rows = $state<Row[]>([emptyRow()]);
	/** The parsed CSV, kept so a mapping change can re-read a column without
	 * asking for the file again. */
	let parsedRecords = $state<Record<string, string>[]>([]);
	let csvHeaders = $state<string[]>([]);
	let mapping = $state<ColumnMapping>(noMapping());
	let importNote = $state('');
	let csvText = $state('');
	let csvError = $state<string | null>(null);
	/** A non-fatal parse problem: the rows loaded, but something about them
	 * needs the editor's eye before importing. */
	let csvWarning = $state<((l: LocaleText) => string) | null>(null);

	const existingIDSet = $derived(new Set(existingExternalIDs));

	const duplicates = $derived(duplicateAcrossRows(rows));

	/** The row rules live in $lib/data/bulkImportRows; this maps the problem they
	 * report onto the locale text for it. */
	function rowError(row: Row, index: number): ((l: LocaleText) => string) | null {
		const problem = rowProblem(row, index, {
			existingExternalIDs: existingIDSet,
			duplicates,
			personUnresolved
		});
		return problem === null ? null : (l) => l.page.bulkImport.row.invalid[problem];
	}

	const allRowsValid = $derived(rows.every((r, i) => rowError(r, i) === null));

	const mintAmount = $derived(mintTotal(rows, submissionTypes));

	const ignoredColumns = $derived(
		csvHeaders.length === 0 ? [] : unmappedHeaders(csvHeaders, mapping)
	);

	/** Required fields nothing is mapped to. Reported rather than blocking on its
	 * own: the row table is editable, so an editor may legitimately fill a column
	 * in by hand instead of mapping one. */
	const missingRequired = $derived(
		csvHeaders.length === 0
			? []
			: (
					[
						['title', 'Title'],
						['externalID', 'External ID']
					] as const
				)
					.filter(([field]) => mapping[field] === null)
					.map(([, label]) => label)
	);

	/** Roles somebody could actually be seated in: the venue's own roles that have
	 * at least one accepted, active volunteer. A role nobody holds cannot receive
	 * a seat, so offering it would only produce rows that fail. */
	const seatableRoles = $derived(
		roles
			.filter((role) =>
				commitments.some((c) => c.roleid === role.id && c.active && c.accepted === 'accepted')
			)
			.sort((a, b) => a.priority - b.priority)
	);

	let personRole = $state<string | undefined>(undefined);

	/** Who a name in the person column may refer to: the chosen role's accepted,
	 * active volunteers, and nobody else. A closed list is what keeps this from
	 * being a search across every scholar on the platform. */
	const candidates = $derived<Candidate[]>(
		personRole === undefined
			? []
			: commitments
					.filter((c) => c.roleid === personRole && c.active && c.accepted === 'accepted')
					.map((c) => ({ id: c.scholarid, name: c.scholars?.name ?? '' }))
					.filter((c) => c.name.length > 0)
	);

	/** What each row's person cell resolves to. A choice the editor pinned wins,
	 * but only while it is still one of the current candidates — so changing the
	 * role cannot leave a stale scholar attached to a row. */
	const personMatches = $derived(
		rows.map((row) => {
			// With no role chosen there is nothing to seat anybody in, so the column
			// is inert rather than every row failing to match an empty candidate list.
			if (personRole === undefined) return { status: 'none' } as const;
			if (row.personChoice !== null && candidates.some((c) => c.id === row.personChoice))
				return { status: 'resolved', id: row.personChoice } as const;
			return matchPersonName(row.person, candidates);
		})
	);

	/** A person column was mapped but no role chosen, so the names in it would be
	 * read and then ignored. Worth saying out loud rather than importing silently
	 * without seating anybody. */
	const personRoleMissing = $derived(mapping.person !== null && personRole === undefined);

	/** Rows naming somebody the venue could not identify. These block the import:
	 * seating the wrong person is a worse outcome than making the editor fix the
	 * name. */
	const personUnresolved = $derived(
		new Set(
			personMatches
				.map((match, index) =>
					match.status === 'resolved' || match.status === 'none' ? -1 : index
				)
				.filter((index) => index >= 0)
		)
	);

	/** Rewrite only the field whose column changed. The row table is editable, and
	 * rebuilding every row would throw away corrections the editor has already
	 * made to the other columns. */
	function remap(field: ImportField, header: string | undefined) {
		mapping = { ...mapping, [field]: header ?? null };
		const fresh = rowsFromParsed(parsedRecords, mapping, submissionTypes, defaultSubmissionType);
		rows = rows.map((row, index) => {
			const source = fresh[index];
			if (source === undefined) return row;
			switch (field) {
				case 'title':
					return { ...row, title: source.title };
				case 'externalID':
					return { ...row, externalID: source.externalID };
				case 'expertise':
					return { ...row, expertise: source.expertise };
				case 'submissionType':
					return { ...row, submissionType: source.submissionType };
				case 'previousID':
					return { ...row, previousID: source.previousID };
				case 'note':
					return { ...row, note: source.note };
				case 'person':
					// A new column means the pinned choice was made about other text.
					return { ...row, person: source.person, personChoice: null };
				default:
					return row;
			}
		});
	}

	/** The menu offered for one field: every column in the file, plus the choice
	 * to import nothing into it. */
	function columnOptions(l: LocaleText) {
		return [
			{ value: undefined, label: l.page.bulkImport.options.unmapped },
			...csvHeaders.map((header) => ({ value: header, label: header }))
		];
	}

	function addRow() {
		rows = [...rows, emptyRow()];
	}

	function removeRow(index: number) {
		rows = rows.filter((_, i) => i !== index);
		if (rows.length === 0) rows = [emptyRow()];
	}

	function applyDefaultType() {
		rows = rows.map((r) => ({ ...r, submissionType: defaultSubmissionType }));
	}

	function ingestCSV(text: string) {
		csvError = null;
		csvWarning = null;
		try {
			const { rows: parsed, ragged } = parseCSV(text);
			if (parsed.length === 0) {
				csvError = 'No rows found in CSV';
				return;
			}
			parsedRecords = parsed;
			csvHeaders = Object.keys(parsed[0]);
			// A guess, not a decision: every column stays changeable below.
			mapping = guessMapping(csvHeaders, MappedFields);
			rows = rowsFromParsed(parsed, mapping, submissionTypes, defaultSubmissionType).map((r) => ({
				...r,
				personChoice: null
			}));
			// A misaligned row still imports — the editor may want to fix it in the
			// table below rather than re-export — but it must not do so quietly.
			// An unquoted comma shifts every column and pushes the last field off
			// the end, which otherwise looked like a clean import.
			if (ragged.length > 0) {
				const lines = ragged.map((r) => r.line).join(', ');
				csvWarning = (l) => l.page.bulkImport.feedback.raggedRows.replace('{lines}', lines);
			}
		} catch (e) {
			csvError = e instanceof Error ? e.message : 'Failed to parse CSV';
		}
	}

	async function handleFileUpload(event: Event) {
		const input = event.target as HTMLInputElement;
		const file = input.files?.[0];
		if (!file) return;
		const text = await file.text();
		ingestCSV(text);
		input.value = '';
	}

	function pasteCSV() {
		if (csvText.trim().length === 0) {
			csvError = 'Paste CSV content first';
			return;
		}
		ingestCSV(csvText);
	}
</script>

<Paragraph text={(l) => l.page.bulkImport.paragraph.intro} />

<h3><Text path={(l) => l.page.bulkImport.header.csv} /></h3>
<Note path={(l) => l.page.bulkImport.note.csv} />

<Form>
	<FileInput
		label={(l) => l.page.bulkImport.field.csvUpload.label}
		accept=".csv,text/csv"
		onChange={handleFileUpload}
	/>

	<TextField strings={(l) => l.page.bulkImport.field.csvPaste} size={60} bind:text={csvText} />
	<Button
		strings={(l) => l.page.bulkImport.button.parseCSV}
		active={csvText.trim().length > 0}
		action={pasteCSV}
	/>

	{#if csvError}
		<Feedback error text={() => csvError ?? ''} />
	{/if}

	{#if csvWarning}
		<Feedback warning text={csvWarning} testid="csv-ragged-warning" />
	{/if}
</Form>

{#if csvHeaders.length > 0}
	<h3><Text path={(l) => l.page.bulkImport.header.mapping} /></h3>
	<Note path={(l) => l.page.bulkImport.note.mapping} />

	<Form>
		<Options
			strings={(l) => l.page.bulkImport.options.mapField.title}
			options={columnOptions(locale())}
			value={mapping.title ?? undefined}
			onChange={(header) => remap('title', header)}
		/>
		<Options
			strings={(l) => l.page.bulkImport.options.mapField.externalID}
			options={columnOptions(locale())}
			value={mapping.externalID ?? undefined}
			onChange={(header) => remap('externalID', header)}
		/>
		<Options
			strings={(l) => l.page.bulkImport.options.mapField.submissionType}
			options={columnOptions(locale())}
			value={mapping.submissionType ?? undefined}
			onChange={(header) => remap('submissionType', header)}
		/>
		<Options
			strings={(l) => l.page.bulkImport.options.mapField.expertise}
			options={columnOptions(locale())}
			value={mapping.expertise ?? undefined}
			onChange={(header) => remap('expertise', header)}
		/>
		<Options
			strings={(l) => l.page.bulkImport.options.mapField.previousID}
			options={columnOptions(locale())}
			value={mapping.previousID ?? undefined}
			onChange={(header) => remap('previousID', header)}
		/>
		<Options
			strings={(l) => l.page.bulkImport.options.mapField.note}
			options={columnOptions(locale())}
			value={mapping.note ?? undefined}
			onChange={(header) => remap('note', header)}
		/>

		{#if seatableRoles.length > 0}
			<Options
				strings={(l) => l.page.bulkImport.options.mapField.person}
				options={columnOptions(locale())}
				value={mapping.person ?? undefined}
				onChange={(header) => remap('person', header)}
			/>
		{/if}

		{#if missingRequired.length > 0}
			<Feedback
				warning
				testid="mapping-missing-required"
				text={(l) =>
					l.page.bulkImport.feedback.missingRequired.replace(
						'{fields}',
						missingRequired.join(', ')
					)}
			/>
		{/if}

		{#if ignoredColumns.length > 0}
			<Feedback
				testid="mapping-ignored-columns"
				text={(l) =>
					l.page.bulkImport.feedback.ignoredColumns.replace('{columns}', ignoredColumns.join(', '))}
			/>
		{/if}
	</Form>
{/if}

<h3><Text path={(l) => l.page.bulkImport.header.defaults} /></h3>

<Form>
	<Options
		strings={(l) => l.page.bulkImport.options.defaultSubmissionType}
		bind:value={defaultSubmissionType}
		options={submissionTypes.map((type) => ({ value: type.id, label: type.name }))}
	/>
	<Button strings={(l) => l.page.bulkImport.button.applyDefault} action={applyDefaultType} />

	{#if seatableRoles.length > 0}
		<Options
			strings={(l) => l.page.bulkImport.options.personRole}
			options={[
				{ value: undefined, label: locale().page.bulkImport.options.unmapped },
				...seatableRoles.map((role) => ({ value: role.id, label: role.name }))
			]}
			value={personRole}
			onChange={(role) => (personRole = role)}
		/>
		<Note path={(l) => l.page.bulkImport.person.note} />
		{#if personRoleMissing}
			<Feedback
				warning
				testid="person-role-missing"
				text={(l) => l.page.bulkImport.person.roleMissing}
			/>
		{/if}
	{:else}
		<Feedback text={(l) => l.page.bulkImport.person.noRole} />
	{/if}
</Form>

<h3><Text path={(l) => l.page.bulkImport.header.rows} /></h3>

<Table>
	{#snippet header()}
		<th><Text path={(l) => l.page.bulkImport.column.title} /></th>
		<th><Text path={(l) => l.page.bulkImport.column.externalID} /></th>
		<th><Text path={(l) => l.page.bulkImport.column.expertise} /></th>
		<th><Text path={(l) => l.page.bulkImport.column.submissionType} /></th>
		<th><Text path={(l) => l.page.bulkImport.column.person} /></th>
		<th><Text path={(l) => l.page.bulkImport.column.previousID} /></th>
		<th><Text path={(l) => l.page.bulkImport.column.note} /></th>
		<th></th>
	{/snippet}
	{#each rows as row, index (index)}
		{@const err = rowError(row, index)}
		<tr data-testid="import-row-{index}">
			<td>
				<TextField
					strings={(l) => ({ ...l.page.bulkImport.field.title, label: '' })}
					bind:text={row.title}
					testid="import-row-{index}-title"
				/>
			</td>
			<td>
				<TextField
					strings={(l) => ({ ...l.page.bulkImport.field.externalID, label: '' })}
					bind:text={row.externalID}
					testid="import-row-{index}-externalid"
				/>
			</td>
			<td>
				<TextField
					strings={(l) => ({ ...l.page.bulkImport.field.expertise, label: '' })}
					bind:text={row.expertise}
				/>
			</td>
			<td>
				<Options
					strings={(l) => ({ ...l.page.bulkImport.options.submissionType, label: '' })}
					bind:value={row.submissionType}
					options={submissionTypes.map((t) => ({ value: t.id, label: t.name }))}
				/>
			</td>
			<td>
				{#if seatableRoles.length > 0}
					{@const match = personMatches[index]}
					<TextField
						strings={(l) => ({ ...l.page.bulkImport.field.person, label: '' })}
						bind:text={row.person}
						testid="import-row-{index}-person"
					/>
					{#if match.status === 'resolved'}
						<ScholarLink id={match.id} size="small" />
					{:else if match.status === 'ambiguous'}
						<Feedback text={(l) => l.page.bulkImport.person.ambiguous} />
						{#each match.candidates as candidate (candidate.id)}
							<Button
								strings={(l) => ({
									label: candidate.name,
									tip: l.widget.scholarSearch.choose.tip
								})}
								action={() => (row.personChoice = candidate.id)}
							/>
						{/each}
					{:else if match.status === 'unmatched'}
						<Feedback
							error
							text={(l) =>
								l.page.bulkImport.person.unmatched.replace(
									'{role}',
									seatableRoles.find((r) => r.id === personRole)?.name ?? ''
								)}
						/>
					{/if}
				{/if}
			</td>
			<td>
				<TextField
					strings={(l) => ({ ...l.page.bulkImport.field.previousID, label: '' })}
					bind:text={row.previousID}
				/>
			</td>
			<td>
				<TextField
					strings={(l) => ({ ...l.page.bulkImport.field.note, label: '' })}
					bind:text={row.note}
				/>
			</td>
			<td>
				<Button
					strings={(l) => l.page.bulkImport.button.removeRow}
					active={rows.length > 1}
					action={() => removeRow(index)}
				/>
			</td>
		</tr>
		{#if err}
			<tr>
				<td colspan="8">
					<Feedback error text={err} />
				</td>
			</tr>
		{/if}
	{/each}
</Table>

<Form>
	<Button
		strings={(l) => l.page.bulkImport.button.addRow}
		testid="bulk-import-add-row"
		action={addRow}
	/>
</Form>

<h3><Text path={(l) => l.page.bulkImport.header.submit} /></h3>

<Paragraph
	text={(l) =>
		l.page.bulkImport.paragraph.mintSummary
			.replaceAll('{count}', rows.length.toString())
			.replaceAll('{total}', mintAmount.toString())}
/>

<Form>
	<TextField strings={(l) => l.page.bulkImport.field.importNote} size={60} bind:text={importNote} />

	<Button
		strings={(l) => l.page.bulkImport.button.submit}
		testid="bulk-import-submit"
		active={allRowsValid}
		action={async () => {
			const result = await handle(
				db().bulkImportSubmissions(
					venue.id,
					rows.map((r, index) => {
						const match = personMatches[index];
						return {
							title: r.title.trim(),
							externalID: r.externalID.trim(),
							previousID: r.previousID.trim() === '' ? null : r.previousID.trim(),
							expertise: r.expertise.trim() === '' ? null : r.expertise.trim(),
							submission_type: r.submissionType,
							note: r.note.trim() === '' ? null : r.note.trim(),
							// Only a confidently resolved name is sent. Anything else
							// already blocked the submit button above.
							person: match.status === 'resolved' ? match.id : null,
							person_role: match.status === 'resolved' ? (personRole ?? null) : null
						};
					}),
					importNote.trim() === '' ? null : importNote.trim()
				)
			);
			if (result) {
				goto(`/venue/${venuePath(venue)}/submissions`);
			}
		}}
	/>
</Form>
