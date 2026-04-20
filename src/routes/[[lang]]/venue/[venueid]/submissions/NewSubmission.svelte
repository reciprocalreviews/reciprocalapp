<script module lang="ts">
	type Charge = { scholar: string; payment: number };
</script>

<!-- svelte-ignore state_referenced_locally -->
<script lang="ts">
	import type { SubmissionType, SubmissionTypeID, VenueRow } from '$data/types';
	import Button from '$lib/components/Button.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import Form from '$lib/components/Form.svelte';
	import Loading from '$lib/components/Loading.svelte';
	import Note from '$lib/components/Note.svelte';
	import Options from '$lib/components/Options.svelte';
	import Paragraph from '$lib/components/Paragraph.svelte';
	import ScholarLink from '$lib/components/ScholarLink.svelte';
	import Slider from '$lib/components/Slider.svelte';
	import Table from '$lib/components/Table.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import { getDB } from '$lib/data/CRUD';
	import { ORCIDRegex } from '$lib/data/ORCID';
	import type Locale from '$lib/locales/Locale';
	import Text from '$lib/locales/Text.svelte';
	import { isntEmpty, validORCID } from '$lib/validation';
	import { getAuth } from '$routes/Auth.svelte';
	import { handle } from '$routes/feedback.svelte';

	let { venue, submissionTypes }: { venue: VenueRow; submissionTypes: SubmissionType[] } = $props();

	const db = getDB();
	const auth = getAuth();
	const user = $derived(auth().getUserID());

	/** The title of the submission we're adding */
	let title = $state('');
	let expertise = $state('');
	let externalID = $state('');
	let previousID = $state('');
	let submissionType = $state<SubmissionTypeID>(submissionTypes[0].id);
	let charges = $state<Charge[]>([{ scholar: '', payment: 0 }]);

	type ScholarState =
		| { status: 'idle' }
		| { status: 'loading' }
		| { status: 'found'; id: string }
		| { status: 'notfound' };

	let scholarStates = $state<ScholarState[]>([{ status: 'idle' }]);

	async function lookupScholar(index: number, orcid: string) {
		if (!validORCID(orcid)) return;
		scholarStates[index] = { status: 'loading' };
		const { data } = await db().findScholar(orcid);
		scholarStates[index] = data ? { status: 'found', id: data } : { status: 'notfound' };
	}

	/** True if the specified charges can be afforded, undefined if checking, string describing the problem. */
	let affordable = $state<((l: Locale) => string) | undefined | true>(undefined);

	/** When charges change, reset affordable */
	$effect(() => {
		if (charges) affordable = undefined;
	});

	function validExternalID(id: string) {
		return id.length > 0;
	}

	function validCharges(charges: Charge[], cost: number) {
		return cost === 0 || (validChargeFormat(charges) && validCharge(charges, cost));
	}

	function validChargeFormat(charges: Charge[]) {
		return (
			charges.length === 0 ||
			charges.every((charge) => {
				return ORCIDRegex.test(charge.scholar) && !isNaN(charge.payment);
			})
		);
	}

	function duplicateScholars(charges: Charge[]) {
		const scholars = charges.map((charge) => charge.scholar);
		return new Set(scholars).size !== scholars.length;
	}

	function validCharge(charges: Charge[], cost: number) {
		return (
			charges.length === 0 || charges.reduce((sum, charge) => sum + charge.payment, 0) === cost
		);
	}

	async function checkAffordability() {
		affordable = undefined;
		const { data, error } = await db().verifyCharges(charges);

		if (error) affordable = () => error.message;
		else if (data === undefined) {
			affordable = (l) => l.page.newSubmission.error.balanceCheck;
		} else if (data !== true) {
			const notFound = data
				.filter((result) => result.payment === undefined)
				.map((result) => result.scholar);
			const short = data
				.filter((result) => result.payment !== undefined && result.payment < 0)
				.map((result) => result.scholar);
			if (notFound.length > 0)
				affordable = (l) =>
					l.page.newSubmission.error.notFound.replace('{scholars}', notFound.join(', '));
			else if (short.length > 0)
				affordable = (l) =>
					l.page.newSubmission.error.insufficentFunds.replace('{short}', short.join(', '));
		} else {
			affordable = true;
		}
	}

	function validSubmission(title: string, externalID: string, charges: Charge[], cost: number) {
		return (
			isntEmpty(title) &&
			validExternalID(externalID) &&
			(previousID.length === 0 || validExternalID(previousID)) &&
			validCharges(charges, cost)
		);
	}
</script>

<Paragraph text={(l) => l.page.newSubmission.paragraph.intro} />

<Form>
	<h3><Text path={(l) => l.page.newSubmission.header.details} /></h3>
	<TextField
		strings={(l) => l.page.submissions.field.title}
		size={40}
		bind:text={title}
		valid={(text) => (isntEmpty(text) ? undefined : (l) => l.page.submissions.field.title.invalid)}
	/>
	<TextField strings={(l) => l.page.submissions.field.expertise} size={40} bind:text={expertise} />
	<TextField
		strings={(l) => l.page.submissions.field.manuscriptID}
		size={40}
		bind:text={externalID}
		valid={(text) =>
			validExternalID(text) ? undefined : (l) => l.page.submissions.field.manuscriptID.invalid}
	/>
	<TextField
		strings={(l) => l.page.submissions.field.previousID}
		size={40}
		bind:text={previousID}
	/>
	<Options
		strings={(l) => l.page.newSubmission.options.submissionType}
		bind:value={submissionType}
		options={submissionTypes.map((type) => ({ value: type.id, label: type.name }))}
	></Options>

	<h3><Text path={(l) => l.page.newSubmission.header.payment} /></h3>
	<Note path={(l) => l.page.newSubmission.note.payment} />
	<Table>
		{#snippet header()}
			<th><Text path={(l) => l.page.newSubmission.table.orcid} /></th>
			<th><Text path={(l) => l.page.newSubmission.table.name} /></th>
			<th><Text path={(l) => l.page.newSubmission.table.payment} /></th>
			<th><Text path={(l) => l.page.newSubmission.table.removeAuthor} /></th>
		{/snippet}
		{#each charges as charge, index}
			<tr class="charge">
				<td>
					<TextField
						strings={(l) => ({ ...l.page.newSubmission.field.authorOrcid, label: undefined })}
						size={24}
						bind:text={charge.scholar}
						valid={(text) => {
							if (!validORCID(text))
								return (l) => l.page.newSubmission.field.authorOrcid.invalid ?? '';
							if (scholarStates[index]?.status === 'notfound')
								return (l) => l.page.newSubmission.field.authorOrcid.unknownScholar;
							return undefined;
						}}
						done={() => lookupScholar(index, charge.scholar)}
					/>
				</td>
				<td class="scholar-name">
					{#if scholarStates[index]?.status === 'loading'}
						<Loading />
					{:else if scholarStates[index]?.status === 'found'}
						<ScholarLink id={scholarStates[index].id} />
					{:else}&mdash;
					{/if}
				</td>
				<td
					><Slider
						strings={(l) => ({ ...l.page.newSubmission.slider.payment, label: undefined })}
						bind:value={charge.payment}
						min={0}
						max={venue.submission_cost}
						step={1}
					/></td
				>
				<td
					><Button
						strings={(l) => l.page.newSubmission.button.removeAuthor}
						active={charges.length > 1}
						action={() => {
							charges.splice(index, 1);
							scholarStates.splice(index, 1);
						}}
					/>
				</td>
			</tr>
		{/each}
	</Table>

	<Button
		strings={(l) => l.page.newSubmission.button.addAuthor}
		action={() => {
			charges.push({ scholar: '', payment: 0 });
			scholarStates.push({ status: 'idle' });
		}}
	/>

	{#if duplicateScholars(charges)}
		<Feedback error text={(l) => l.page.newSubmission.feedback.duplicateScholars}></Feedback>
	{:else if charges.reduce((sum, charge) => sum + charge.payment, 0) < venue.submission_cost}
		<Feedback
			error
			text={(l) =>
				l.page.newSubmission.feedback.incompletePayment.replace(
					'{deficit}',
					(
						venue.submission_cost - charges.reduce((sum, charge) => sum + charge.payment, 0)
					).toString()
				)}
		/>
	{:else}
		<Note path={(l) => l.page.newSubmission.note.balance} />

		<Button
			strings={(l) => l.page.newSubmission.button.checkBalances}
			active={validChargeFormat(charges) &&
				validCharge(charges, venue.submission_cost) &&
				affordable !== true}
			action={checkAffordability}
		/>

		{#if typeof affordable === 'function'}<Feedback error text={affordable} />{/if}
	{/if}

	<h3><Text path={(l) => l.page.newSubmission.header.submit} /></h3>

	<Note path={(l) => l.page.newSubmission.note.approve} />

	<Button
		strings={(l) => l.page.newSubmission.button.submit}
		active={affordable === true &&
			validSubmission(title, externalID, charges, venue.submission_cost)}
		action={async () => {
			if (user) {
				const result = await handle(
					db().createSubmission(
						user,
						title,
						expertise,
						venue.id,
						externalID,
						previousID,
						submissionType,
						charges
					)
				);

				// Reset form if successful.
				if (result) {
					title = '';
					expertise = '';
					externalID = '';
					previousID = '';
					charges = [];
					affordable = undefined;
				}

				return result;
			}
		}}
	/>
</Form>

<style>
	.charge td {
		vertical-align: baseline;
	}
</style>
