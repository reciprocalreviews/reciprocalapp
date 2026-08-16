<!-- svelte-ignore state_referenced_locally -->
<script lang="ts">
	import { goto } from '$app/navigation';
	import type { SubmissionType, SubmissionTypeID, VenueRow } from '$data/types';
	import Button from '$lib/components/Button.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import FileInput from '$lib/components/FileInput.svelte';
	import Form from '$lib/components/Form.svelte';
	import Note from '$lib/components/Note.svelte';
	import Options from '$lib/components/Options.svelte';
	import Paragraph from '$lib/components/Paragraph.svelte';
	import Table from '$lib/components/Table.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import { getDB } from '$lib/data/CRUD';
	import {
		duplicateAcrossRows,
		mintAmount as mintTotal,
		rowError as rowProblem,
		rowsFromParsed
	} from '$lib/data/bulkImportRows';
	import parseCSV from '$lib/data/parseCSV';
	import type LocaleText from '$lib/locales/Locale';
	import Text from '$lib/locales/Text.svelte';
	import { handle } from '$routes/feedback.svelte';

	let {
		venue,
		submissionTypes,
		existingExternalIDs
	}: {
		venue: VenueRow;
		submissionTypes: SubmissionType[];
		existingExternalIDs: string[];
	} = $props();

	const db = getDB();

	type Row = {
		title: string;
		externalID: string;
		expertise: string;
		submissionType: SubmissionTypeID;
		previousID: string;
		note: string;
	};

	function emptyRow(): Row {
		return {
			title: '',
			externalID: '',
			expertise: '',
			submissionType: defaultSubmissionType,
			previousID: '',
			note: ''
		};
	}

	let defaultSubmissionType = $state<SubmissionTypeID>(submissionTypes[0].id);
	let rows = $state<Row[]>([emptyRow()]);
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
		const problem = rowProblem(row, index, { existingExternalIDs: existingIDSet, duplicates });
		return problem === null ? null : (l) => l.page.bulkImport.row.invalid[problem];
	}

	const allRowsValid = $derived(rows.every((r, i) => rowError(r, i) === null));

	const mintAmount = $derived(mintTotal(rows, submissionTypes));

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
			rows = rowsFromParsed(parsed, submissionTypes, defaultSubmissionType);
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
		<Feedback error text={csvWarning} testid="csv-ragged-warning" />
	{/if}
</Form>

<h3><Text path={(l) => l.page.bulkImport.header.defaults} /></h3>

<Form>
	<Options
		strings={(l) => l.page.bulkImport.options.defaultSubmissionType}
		bind:value={defaultSubmissionType}
		options={submissionTypes.map((type) => ({ value: type.id, label: type.name }))}
	/>
	<Button strings={(l) => l.page.bulkImport.button.applyDefault} action={applyDefaultType} />
</Form>

<h3><Text path={(l) => l.page.bulkImport.header.rows} /></h3>

<Table>
	{#snippet header()}
		<th><Text path={(l) => l.page.bulkImport.column.title} /></th>
		<th><Text path={(l) => l.page.bulkImport.column.externalID} /></th>
		<th><Text path={(l) => l.page.bulkImport.column.expertise} /></th>
		<th><Text path={(l) => l.page.bulkImport.column.submissionType} /></th>
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
				<td colspan="7">
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
					rows.map((r) => ({
						title: r.title.trim(),
						externalID: r.externalID.trim(),
						previousID: r.previousID.trim() === '' ? null : r.previousID.trim(),
						expertise: r.expertise.trim() === '' ? null : r.expertise.trim(),
						submission_type: r.submissionType,
						note: r.note.trim() === '' ? null : r.note.trim()
					})),
					importNote.trim() === '' ? null : importNote.trim()
				)
			);
			if (result) {
				goto(`/venue/${venue.id}/submissions`);
			}
		}}
	/>
</Form>
