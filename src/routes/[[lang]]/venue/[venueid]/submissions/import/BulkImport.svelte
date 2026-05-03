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
	import parseCSV from '$lib/data/parseCSV';
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

	const existingIDSet = $derived(new Set(existingExternalIDs));

	const duplicateAcrossRows = $derived.by(() => {
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
	});

	function rowError(row: Row, index: number): ((l: import('$lib/locales/Locale').default) => string) | null {
		if (row.title.trim().length === 0) return (l) => l.page.bulkImport.row.invalid.title;
		if (row.externalID.trim().length === 0) return (l) => l.page.bulkImport.row.invalid.externalID;
		if (existingIDSet.has(row.externalID.trim()))
			return (l) => l.page.bulkImport.row.invalid.duplicateExisting;
		if (duplicateAcrossRows.has(index)) return (l) => l.page.bulkImport.row.invalid.duplicateRow;
		return null;
	}

	const allRowsValid = $derived(rows.every((r, i) => rowError(r, i) === null));

	const mintAmount = $derived(venue.submission_cost * rows.length);

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

	function rowsFromParsed(parsed: Record<string, string>[]): Row[] {
		return parsed.map((p) => {
			const typeName = (p.submission_type ?? '').trim().toLowerCase();
			const matched = typeName
				? submissionTypes.find((t) => t.name.toLowerCase() === typeName)
				: null;
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

	function ingestCSV(text: string) {
		csvError = null;
		try {
			const parsed = parseCSV(text);
			if (parsed.length === 0) {
				csvError = 'No rows found in CSV';
				return;
			}
			rows = rowsFromParsed(parsed);
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

	<TextField
		strings={(l) => l.page.bulkImport.field.csvPaste}
		size={60}
		bind:text={csvText}
	/>
	<Button
		strings={(l) => l.page.bulkImport.button.parseCSV}
		active={csvText.trim().length > 0}
		action={pasteCSV}
	/>

	{#if csvError}
		<Feedback error text={() => csvError ?? ''} />
	{/if}
</Form>

<h3><Text path={(l) => l.page.bulkImport.header.defaults} /></h3>

<Form>
	<Options
		strings={(l) => l.page.bulkImport.options.defaultSubmissionType}
		bind:value={defaultSubmissionType}
		options={submissionTypes.map((type) => ({ value: type.id, label: type.name }))}
	/>
	<Button
		strings={(l) => l.page.bulkImport.button.applyDefault}
		action={applyDefaultType}
	/>
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
	<Button strings={(l) => l.page.bulkImport.button.addRow} testid="bulk-import-add-row" action={addRow} />
</Form>

<h3><Text path={(l) => l.page.bulkImport.header.submit} /></h3>

<Paragraph
	text={(l) =>
		l.page.bulkImport.paragraph.mintSummary
			.replaceAll('{count}', rows.length.toString())
			.replaceAll('{cost}', venue.submission_cost.toString())
			.replaceAll('{total}', mintAmount.toString())}
/>

<Form>
	<TextField
		strings={(l) => l.page.bulkImport.field.importNote}
		size={60}
		bind:text={importNote}
	/>

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
