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
		distinctTypeValues,
		duplicateAcrossRows,
		guessTypeAssignments,
		mintAmount as mintTotal,
		rowError as rowProblem,
		rowsFromParsed,
		type ImportRow,
		type TypeAssignments
	} from '$lib/data/bulkImportRows';
	import {
		guessMapping,
		unmappedHeaders,
		type ColumnMapping,
		type ImportField,
		type RoleColumns
	} from '$lib/data/columnMapping';
	import { matchPersonName, type Candidate, type PersonMatch } from '$lib/data/matchPersonName';
	import parseCSV from '$lib/data/parseCSV';
	import type LocaleText from '$lib/locales/Locale';
	import Text from '$lib/locales/Text.svelte';
	import { getLocaleContext } from '$routes/Contexts';
	import { addFeedback, handle } from '$routes/feedback.svelte';
	import { tick } from 'svelte';

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
		/** The name each role's column wrote, keyed by role id, editable here. */
		people: Record<string, string>;
		/** A scholar the editor picked when a name alone was ambiguous, keyed by
		 * role id. Kept separate from the name so the text stays the file's and the
		 * choice stays revocable. */
		peopleChoices: Record<string, string>;
	};

	function emptyRow(): Row {
		return {
			title: '',
			externalID: '',
			expertise: '',
			submissionType: defaultSubmissionType,
			previousID: '',
			note: '',
			people: {},
			peopleChoices: {}
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
		'note'
	];

	function noMapping(): ColumnMapping {
		return {
			title: null,
			externalID: null,
			expertise: null,
			submissionType: null,
			previousID: null,
			note: null
		};
	}

	let defaultSubmissionType = $state<SubmissionTypeID>(submissionTypes[0].id);
	let rows = $state<Row[]>([emptyRow()]);
	/** The parsed CSV, kept so a mapping change can re-read a column without
	 * asking for the file again. */
	let parsedRecords = $state<Record<string, string>[]>([]);
	let csvHeaders = $state<string[]>([]);
	let mapping = $state<ColumnMapping>(noMapping());
	/** Which column names the holder of each venue role. Never guessed — see
	 * guessMapping's note on why a wrong role is not like a wrong title. */
	let roleColumns = $state<RoleColumns>({});
	/** What each distinct value in the type column becomes. */
	let typeAssignments = $state<TypeAssignments>({});
	/** The name of the file that produced the current rows, so the form can say
	 * what it read: the native control is cleared straight after reading (so
	 * re-picking the same file fires `change` again) and goes back to saying no
	 * file is chosen. */
	let loadedFile = $state<string | null>(null);
	/** The matching section, so the page can take the eye to it. The rows appear
	 * below the fold and used to arrive with no signal at all. */
	let matchingSection = $state<HTMLElement | null>(null);
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
		// A person the venue could not identify is reported in the cell itself, where
		// it can name the role that has no such volunteer. Repeating it under the row
		// said the same thing twice and promised suggestions that only exist when a
		// name is ambiguous. It still blocks the import — see allRowsValid.
		if (problem === null || problem === 'personUnresolved') return null;
		return (l) => l.page.bulkImport.row.invalid[problem];
	}

	const mintAmount = $derived(mintTotal(rows, submissionTypes));

	const ignoredColumns = $derived(
		csvHeaders.length === 0 ? [] : unmappedHeaders(csvHeaders, mapping, roleColumns)
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

	/** The distinct values in the matched type column, with how many rows carry
	 * each. Empty when no type column is matched. */
	const typeValues = $derived(distinctTypeValues(parsedRecords, mapping.submissionType));

	/** Values that matched no submission type by name and so took the default —
	 * the case that used to set the mint in silence. */
	const unmatchedTypeValues = $derived(
		typeValues.filter(
			({ value }) => !submissionTypes.some((t) => t.name.toLowerCase() === value.toLowerCase())
		)
	);

	/** The roles that actually have a column, in the venue's own priority order.
	 * These are the columns the row table shows. */
	const matchedRoles = $derived(seatableRoles.filter((role) => roleColumns[role.id] !== undefined));

	/** The venue's top-priority roles. More than one is representable — nothing
	 * constrains roles.priority to be unique within a venue — and with one column
	 * per role an admin could match a column to each, which the database refuses. */
	const topRoles = $derived(seatableRoles.filter((role) => role.priority === 0));

	/** Top roles that both have a column. Caught here rather than at submit: an
	 * admin who has matched four hundred rows should not learn this from an opaque
	 * rollback. */
	const duplicateTopRoles = $derived(topRoles.filter((role) => roleColumns[role.id] !== undefined));

	/** Who a name in a role's column may refer to: that role's accepted, active
	 * volunteers, and nobody else. A closed list is what keeps this from being a
	 * search across every scholar on the platform, which is how you seat the wrong
	 * Andrew. */
	const candidatesByRole = $derived(
		new Map<string, Candidate[]>(
			seatableRoles.map((role) => [
				role.id,
				commitments
					.filter((c) => c.roleid === role.id && c.active && c.accepted === 'accepted')
					.map((c) => ({ id: c.scholarid, name: c.scholars?.name ?? '' }))
					.filter((c) => c.name.length > 0)
			])
		)
	);

	/** What each row's cells resolve to, as row → role id → match.
	 *
	 * Memoized per (role, written name) because matchPersonName re-tokenizes every
	 * candidate on every call: four hundred rows across three roles against sixty
	 * volunteers is tens of thousands of calls, re-run on every keystroke in any
	 * cell. The distinct names in a column are far fewer than its rows. */
	const personMatches = $derived.by(() => {
		const memo = new Map<string, Map<string, PersonMatch>>();
		return rows.map((row) => {
			const matches: Record<string, PersonMatch> = {};
			for (const role of Object.keys(roleColumns)) {
				const candidates = candidatesByRole.get(role) ?? [];
				const written = row.people[role] ?? '';
				// A choice the editor pinned wins, but only while it is still one of
				// this role's candidates — so changing a column cannot leave a stale
				// scholar attached to a row.
				const pinned = row.peopleChoices[role];
				if (pinned !== undefined && candidates.some((c) => c.id === pinned)) {
					matches[role] = { status: 'resolved', id: pinned };
					continue;
				}
				let byName = memo.get(role);
				if (byName === undefined) {
					byName = new Map();
					memo.set(role, byName);
				}
				let match = byName.get(written);
				if (match === undefined) {
					match = matchPersonName(written, candidates);
					byName.set(written, match);
				}
				matches[role] = match;
			}
			return matches;
		});
	});

	/** Rows where a name matched several of the venue's volunteers and nobody has
	 * chosen between them. These block the import, because this is the one case
	 * where the wrong person could be seated: the file clearly means somebody the
	 * venue knows, and picking for the editor would be a guess. Choosing is one
	 * click. */
	const personUnresolved = $derived(
		new Set(
			personMatches
				.map((matches, index) =>
					Object.values(matches).some((m) => m.status === 'ambiguous') ? index : -1
				)
				.filter((index) => index >= 0)
		)
	);

	/** How many rows name somebody nobody at this venue matches, per role.
	 *
	 * These deliberately block nothing. An unmatched name seats NOBODY, so there
	 * is no wrong person to seat — the reasoning that justifies blocking an
	 * ambiguous name does not carry over, and applying it here refused the import
	 * outright in exactly the case the feature exists for: a backlog whose editors
	 * have not signed up yet, where every row names somebody the platform has
	 * never heard of. Those submissions import unseated and carry the venue's
	 * existing waiting-for-an-editor flag, which is what that flag is for. The
	 * count is reported before submitting, since importing without editors should
	 * be a thing the editor decided rather than noticed later. */
	const unmatchedByRole = $derived(
		matchedRoles
			.map((role) => ({
				role,
				count: personMatches.filter((matches) => matches[role.id]?.status === 'unmatched').length
			}))
			.filter(({ count }) => count > 0)
	);

	const allRowsValid = $derived(
		rows.every(
			(r, i) =>
				rowProblem(r, i, {
					existingExternalIDs: existingIDSet,
					duplicates,
					personUnresolved
				}) === null
		) && duplicateTopRoles.length < 2
	);

	/** Rows seating one person in two roles. Allowed — they did both jobs — but
	 * worth saying, because it is two payments for one paper and an import is
	 * exactly where the mistake gets made fifty times at once. */
	const doubleSeated = $derived(
		new Set(
			personMatches
				.map((matches, index) => {
					const ids = Object.values(matches)
						.filter((m) => m.status === 'resolved')
						.map((m) => (m.status === 'resolved' ? m.id : ''));
					return new Set(ids).size === ids.length ? -1 : index;
				})
				.filter((index) => index >= 0)
		)
	);

	/** Every row rebuilt from the current matching. Used only to copy one field
	 * out of; never assigned wholesale, since the row table is editable and
	 * rebuilding would throw away corrections the editor has already made. */
	function rebuilt(): ImportRow[] {
		return rowsFromParsed(
			parsedRecords,
			mapping,
			roleColumns,
			defaultSubmissionType,
			typeAssignments
		);
	}

	/** Rewrite only the field whose column changed. */
	function remap(field: ImportField, header: string | undefined) {
		mapping = { ...mapping, [field]: header ?? null };
		if (field === 'submissionType') {
			// A different type column means different values to resolve.
			typeAssignments = guessTypeAssignments(typeValues, submissionTypes, defaultSubmissionType);
		}
		const fresh = rebuilt();
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
				default:
					return row;
			}
		});
	}

	/** Rewrite only one role's names. A new column means any pinned choice for
	 * that role was made about text that is no longer there. */
	function remapRole(role: string, header: string | undefined) {
		const next = { ...roleColumns };
		if (header === undefined) delete next[role];
		else next[role] = header;
		roleColumns = next;

		const fresh = rowsFromParsed(
			parsedRecords,
			mapping,
			roleColumns,
			defaultSubmissionType,
			typeAssignments
		);
		rows = rows.map((row, index) => {
			const people = { ...row.people };
			const choices = { ...row.peopleChoices };
			delete choices[role];
			if (header === undefined) delete people[role];
			else people[role] = fresh[index]?.people[role] ?? '';
			return { ...row, people, peopleChoices: choices };
		});
	}

	/** Rewrite every row's type from the current value assignments. */
	function reassignType(value: string, type: string | undefined) {
		if (type === undefined) return;
		typeAssignments = { ...typeAssignments, [value.toLowerCase()]: type };
		const fresh = rebuilt();
		rows = rows.map((row, index) =>
			fresh[index] === undefined ? row : { ...row, submissionType: fresh[index].submissionType }
		);
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

	async function ingestCSV(text: string, name: string) {
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
			// A guess, not a decision: every column stays changeable below. Role
			// columns are deliberately not guessed at all.
			mapping = guessMapping(csvHeaders, MappedFields);
			roleColumns = {};
			typeAssignments = guessTypeAssignments(
				distinctTypeValues(parsed, mapping.submissionType),
				submissionTypes,
				defaultSubmissionType
			);
			rows = rowsFromParsed(
				parsed,
				mapping,
				roleColumns,
				defaultSubmissionType,
				typeAssignments
			).map((r) => ({ ...r, peopleChoices: {} }));
			loadedFile = name;

			// A misaligned row still imports — the editor may want to fix it in the
			// table below rather than re-export — but it must not do so quietly.
			// An unquoted comma shifts every column and pushes the last field off
			// the end, which otherwise looked like a clean import.
			if (ragged.length > 0) {
				const lines = ragged.map((r) => r.line).join(', ');
				csvWarning = (l) => l.page.bulkImport.feedback.raggedRows.replace('{lines}', lines);
			}

			// Say that something happened. Banners is an aria-live region, so this is
			// spoken as well as seen — and reading a file used to produce no output at
			// all unless it failed, while the native file control goes back to saying
			// no file is chosen the moment we clear it below.
			addFeedback(
				locale()
					.page.bulkImport.feedback.loaded.replace('{count}', parsed.length.toString())
					.replace('{name}', name),
				'success'
			);

			// And take the eye to what appeared, which is otherwise below the fold.
			// The section is revealed by an {#if} in this same tick, so it does not
			// exist yet — tick() is doing here what Page's requestAnimationFrame does
			// for the hash pattern, which does not apply because this is content
			// appearing in place rather than an anchor to a stable heading.
			await tick();
			matchingSection?.scrollIntoView({ behavior: 'smooth', block: 'start' });
		} catch (e) {
			csvError = e instanceof Error ? e.message : 'Failed to parse CSV';
		}
	}

	async function handleFileUpload(event: Event) {
		const input = event.target as HTMLInputElement;
		const file = input.files?.[0];
		if (!file) return;
		const text = await file.text();
		await ingestCSV(text, file.name);
		// Cleared so re-picking the same file fires `change` again. This is also what
		// makes the native control say no file is chosen, which is why the form says
		// what it read itself.
		input.value = '';
	}

	function pasteCSV() {
		if (csvText.trim().length === 0) {
			csvError = 'Paste CSV content first';
			return;
		}
		void ingestCSV(csvText, locale().page.bulkImport.feedback.pastedSource);
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

	<!-- inline={false} renders a textarea. As a single-line input this field could
	     not hold a CSV at all: pasting multi-line text into an <input> flattens it
	     to one line, so every paste arrived as a header with no rows. Wrapped and
	     capped because the textarea grows to its content, and a real export is
	     hundreds of lines — it pushed the whole form off the screen. -->
	<div class="paste">
		<TextField
			strings={(l) => l.page.bulkImport.field.csvPaste}
			size={60}
			inline={false}
			testid="bulk-import-paste"
			bind:text={csvText}
		/>
	</div>
	<Button
		strings={(l) => l.page.bulkImport.button.parseCSV}
		testid="bulk-import-parse"
		active={csvText.trim().length > 0}
		action={pasteCSV}
	/>

	{#if csvError}
		<Feedback error text={() => csvError ?? ''} />
	{/if}

	{#if csvWarning}
		<Feedback warning text={csvWarning} testid="csv-ragged-warning" />
	{/if}

	<!-- The banner announcing this is dismissible; the fact is not. -->
	{#if loadedFile !== null}
		<Feedback
			testid="csv-loaded"
			text={(l) => l.page.bulkImport.feedback.loadedFrom}
			inputs={{ name: loadedFile, count: rows.length.toString() }}
		/>
	{/if}
</Form>

{#if csvHeaders.length > 0}
	<section bind:this={matchingSection}>
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
					text={(l) => l.page.bulkImport.feedback.ignoredColumns}
					inputs={{ columns: ignoredColumns.join(', ') }}
				/>
			{/if}
		</Form>

		<!-- One column per role, rather than one column and a role: an export often
		     names an editor in chief and a handling editor in separate columns, which
		     are two people in two roles on the same manuscript. -->
		<h3><Text path={(l) => l.page.bulkImport.person.header} /></h3>
		{#if seatableRoles.length > 0}
			<Note path={(l) => l.page.bulkImport.person.note} />
			<Form>
				{#each seatableRoles as role (role.id)}
					<Options
						strings={(l) => ({
							label: (l.page.bulkImport.options.roleColumn.label ?? '').replace('{role}', role.name)
						})}
						options={columnOptions(locale())}
						value={roleColumns[role.id]}
						testid="role-column-{role.id}"
						onChange={(header) => remapRole(role.id, header)}
					/>
				{/each}
				{#if duplicateTopRoles.length > 1}
					<Feedback
						error
						testid="two-top-roles"
						text={(l) => l.page.bulkImport.feedback.twoTopRoles}
						inputs={{ roles: duplicateTopRoles.map((r) => r.name).join(', ') }}
					/>
				{/if}
			</Form>
		{:else}
			<Feedback text={(l) => l.page.bulkImport.person.noRole} />
		{/if}
	</section>
{/if}

<!-- One section, because these are one decision. When the file has a type column
     every distinct value gets a menu and those menus ARE the answer, so there is
     no separate default to compete with them — which matters, because "apply
     default to all" overwrote every row unconditionally and would silently undo
     the matching above it. When there is no type column the default is the only
     thing deciding, so it appears instead. -->
<h3><Text path={(l) => l.page.bulkImport.type.header} /></h3>

{#if typeValues.length > 0}
	<Note path={(l) => l.page.bulkImport.type.note} />
	<Form>
		{#each typeValues as { value, count } (value)}
			<Options
				strings={(l) => ({
					label: l.page.bulkImport.type.value
						.replace('{value}', value)
						.replace('{count}', count.toString())
				})}
				options={submissionTypes.map((type) => ({ value: type.id, label: type.name }))}
				value={typeAssignments[value.toLowerCase()] ?? defaultSubmissionType}
				testid="type-value-{value}"
				onChange={(type) => reassignType(value, type)}
			/>
		{/each}
		{#if unmatchedTypeValues.length > 0}
			<Feedback
				testid="type-values-unmatched"
				text={(l) => l.page.bulkImport.type.unmatched}
				inputs={{ values: unmatchedTypeValues.map((v) => v.value).join(', ') }}
			/>
		{/if}
	</Form>
{:else}
	<Note path={(l) => l.page.bulkImport.type.noColumn} />
	<Form>
		<Options
			strings={(l) => l.page.bulkImport.options.defaultSubmissionType}
			bind:value={defaultSubmissionType}
			options={submissionTypes.map((type) => ({ value: type.id, label: type.name }))}
		/>
		<Button strings={(l) => l.page.bulkImport.button.applyDefault} action={applyDefaultType} />
	</Form>
{/if}

<h3><Text path={(l) => l.page.bulkImport.header.rows} /></h3>

<!-- Said once here rather than once per row: the cells are barely wider than a
     word, so they carry only the fact and this carries the consequence. -->
{#if matchedRoles.length > 0}
	<Note path={(l) => l.page.bulkImport.person.unmatchedNote} />
{/if}

<!-- Table has no scroll container of its own (its only escape hatch is the opt-in
     `full` viewport bleed). This table grows a column per matched role, each with a
     min-width, so past two or three roles it would otherwise push its right-hand
     columns off the page with no way to reach them. -->
<div class="rows">
	<Table>
		{#snippet header()}
			<th><Text path={(l) => l.page.bulkImport.column.title} /></th>
			<th><Text path={(l) => l.page.bulkImport.column.externalID} /></th>
			<th><Text path={(l) => l.page.bulkImport.column.expertise} /></th>
			<th><Text path={(l) => l.page.bulkImport.column.submissionType} /></th>
			{#each matchedRoles as role (role.id)}
				<th class="person">{role.name}</th>
			{/each}
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
				{#each matchedRoles as role (role.id)}
					{@const match = personMatches[index][role.id] ?? { status: 'none' }}
					<td class="person">
						<TextField
							strings={(l) => ({ ...l.page.bulkImport.field.person, label: '' })}
							bind:text={row.people[role.id]}
							testid="import-row-{index}-person-{role.id}"
						/>
						{#if match.status === 'resolved'}
							<ScholarLink id={match.id} size="small" />
						{:else if match.status === 'ambiguous'}
							<Feedback text={(l) => l.page.bulkImport.person.ambiguous} />
							<div class="matches">
								{#each match.candidates as candidate (candidate.id)}
									<Button
										small
										strings={(l) => ({
											label: candidate.name,
											// The name goes in the tip as well as the label, because the
											// tip is the button's aria-label: a column of buttons all
											// announcing "Choose this scholar" is unusable by voice or
											// screen reader.
											tip: l.widget.scholarSearch.choose.tip.replace('{name}', candidate.name)
										})}
										action={() => (row.peopleChoices[role.id] = candidate.id)}
									/>
								{/each}
							</div>
						{:else if match.status === 'unmatched'}
							<Feedback
								error
								testid="import-row-{index}-unmatched"
								text={(l) => l.page.bulkImport.person.unmatched}
							/>
						{/if}
					</td>
				{/each}
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
					<td colspan={7 + matchedRoles.length}>
						<Feedback error text={err} />
					</td>
				</tr>
			{/if}
			<!-- Allowed, not blocked: somebody who was both the editor and the handling
		     editor did both jobs. But it is two payments for one paper, and an import
		     is where that mistake gets made fifty times at once. -->
			{#if doubleSeated.has(index)}
				<tr>
					<td colspan={7 + matchedRoles.length}>
						<Feedback
							warning
							testid="import-row-{index}-double-seated"
							text={(l) => l.page.bulkImport.person.doubleSeated}
						/>
					</td>
				</tr>
			{/if}
		{/each}
	</Table>
</div>

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

<!-- Importing without editors should be something the editor decided, not
     something they notice afterwards. This is the whole reason an unmatched name
     is allowed to pass. -->
{#each unmatchedByRole as { role, count } (role.id)}
	<Paragraph
		text={(l) =>
			l.page.bulkImport.paragraph.unseated
				.replaceAll('{count}', count.toString())
				.replaceAll('{role}', role.name)}
	/>
{/each}

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
						return {
							title: r.title.trim(),
							externalID: r.externalID.trim(),
							previousID: r.previousID.trim() === '' ? null : r.previousID.trim(),
							expertise: r.expertise.trim() === '' ? null : r.expertise.trim(),
							submission_type: r.submissionType,
							note: r.note.trim() === '' ? null : r.note.trim(),
							// Only a confidently resolved name is sent. Anything else
							// already blocked the submit button above.
							people: Object.entries(personMatches[index]).flatMap(([role, m]) =>
								m.status === 'resolved' ? [{ person: m.id, person_role: role }] : []
							)
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

<style>
	/* The wrapper exists so the matching panel can be scrolled to by reference
	   (see matchingSection). Being an element rather than a fragment makes it the
	   flex item in Page's .content column, which reverts everything inside it to
	   ordinary block flow — so its headings lost the 2rem gap that spaces every
	   other heading on the page. Repeating .content's own layout here restores
	   that, rather than giving h3 a margin globally: the app spaces headings by
	   ancestor gap, so a margin would stack on top of it everywhere. */
	section {
		display: flex;
		flex-direction: column;
		gap: calc(2 * var(--spacing));
	}

	/* The table has no column widths and lays out automatically, so a cell holding
	   a text field and a message collapses to the width of its longest word —
	   "Associate" on its own line, then "Editor" on the next. Wide enough for a
	   name and a short verdict beside it. */
	.person {
		min-width: 11em;
	}

	.rows {
		overflow-x: auto;
	}

	.paste :global(textarea) {
		max-height: 12em;
		overflow-y: auto;
	}

	/* Copied from ScholarMatches, whose rule is scoped to that component: this
	   file borrowed its markup for the candidate buttons but could not borrow its
	   CSS, so they were stacking as unstyled block flow. */
	.matches {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: var(--spacing-half);
	}
</style>
