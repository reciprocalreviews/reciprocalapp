<script module lang="ts">
	type Charge = { scholar: string; payment: number };
</script>

<!-- svelte-ignore state_referenced_locally -->
<script lang="ts">
	import type { SubmissionType, SubmissionTypeID, VenueRow } from '$data/types';
	import Button from '$lib/components/Button.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import Form from '$lib/components/Form.svelte';
	import Note from '$lib/components/Note.svelte';
	import Options from '$lib/components/Options.svelte';
	import Slider from '$lib/components/Slider.svelte';
	import Table from '$lib/components/Table.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import { getDB } from '$lib/data/CRUD';
	import { ORCIDRegex } from '$lib/data/ORCID';
	import { isntEmpty, validORCID } from '$lib/validation';
	import { getAuth } from '../../../Auth.svelte';
	import { handle } from '../../../feedback.svelte';

	let { venue, submissionTypes }: { venue: VenueRow; submissionTypes: SubmissionType[] } = $props();

	const db = getDB();
	const auth = getAuth();
	const user = $derived(auth.getUserID());

	/** The title of the submission we're adding */
	let title = $state('');
	let expertise = $state('');
	let externalID = $state('');
	let previousID = $state('');
	let submissionType = $state<SubmissionTypeID>(submissionTypes[0].id);
	let charges = $state<Charge[]>([{ scholar: '', payment: 0 }]);

	/** True if the specified charges can be afforded, undefined if checking, string describing the problem. */
	let affordable = $state<string | undefined | true>(undefined);

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

		console.log(data);
		console.log(error);

		if (error) affordable = error.message;
		else if (data === undefined) {
			affordable = 'An error occurred while checking balances.';
		} else if (data !== true) {
			affordable =
				'There are not enough tokens to submit: ' +
				data
					.filter((result) => result.payment === undefined || result.payment < 0)
					.map((deficit) =>
						deficit.payment === undefined
							? `${deficit.scholar} could not be found`
							: `${deficit.scholar} is short ${Math.abs(deficit.payment)}`
					)
					.join(', ');
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

<p>
	Ready to create a new submission? Typically, this form is filled by one of the authors of a
	submission, to pay for a submission to be reviewed. After filling out this form:
</p>

<ul>
	<li>The submission will be created in the system.</li>
	<li>All scholars listed will need to confirm their payments.</li>
	<li>Once everyone has paid, the editor will proceed with review.</li>
</ul>

<Form>
	<h3>Details</h3>
	<TextField
		label="submission title"
		size={40}
		placeholder="title"
		bind:text={title}
		valid={(text) => (isntEmpty(text) ? undefined : 'Title must be non-empty.')}
		note="For internal tracking, and bidding if enabled."
	/>
	<TextField
		label="expertise required to review (optional)"
		size={40}
		placeholder="expertise"
		bind:text={expertise}
		note="Help authors and editors find appropriate reviewers."
	/>
	<TextField
		label="manuscript id"
		size={40}
		placeholder="id"
		bind:text={externalID}
		valid={(text) => (validExternalID(text) ? undefined : 'ID must be non-empty.')}
		note="The manuscript's ID from your review system, to link this transaction to your submission."
	/>
	<TextField
		label="previous manuscript id"
		size={40}
		placeholder="id"
		bind:text={previousID}
		note="The ID of the previous submission, if this is a revision and you want to track it."
	/>
	<Options
		label="submission type"
		bind:value={submissionType}
		options={submissionTypes.map((type) => ({ value: type.id, label: type.name }))}
	></Options>

	<!--
								: duplicateScholars(charges)
									? 'Scholars must be unique.'
									: !validCharge(charges, venue.submission_cost)
										? `The charges do not sum to the submission cost of ${venue.submission_cost}`
										: affordable === undefined
											? "When you're done, check balances below."
											: affordable}

					note={affordable === true
					? 'These authors can afford this charge.'
					: `By line, authors and how many tokens to charge each of them. Tokens must sum to ${venue.submission_cost}.`}
 -->
	<h3>Payment</h3>
	<Note>Specify the authors and how many tokens each will pay.</Note>
	<Table>
		{#each charges as charge, index}
			<tr class="charge">
				<td>
					<TextField
						label="author"
						size={24}
						placeholder="ORCID"
						bind:text={charge.scholar}
						valid={(text) => (validORCID(text) ? undefined : 'Invalid ORCID')}
					/>
				</td>
				<td
					><Slider
						label="payment"
						bind:value={charge.payment}
						min={0}
						max={venue.submission_cost}
						step={1}>{charge.payment}</Slider
					></td
				>
				<td
					><Button
						tip="Remove this author from the submission"
						active={charges.length > 1}
						action={() => charges.splice(index, 1)}>x</Button
					>
				</td>
			</tr>
		{/each}
	</Table>

	<Button
		tip="Add another author to the submission"
		action={() => charges.push({ scholar: '', payment: 0 })}>Add author</Button
	>

	{#if duplicateScholars(charges)}
		<Feedback error>Each author must have a unique ORCID.</Feedback>
	{:else if charges.reduce((sum, charge) => sum + charge.payment, 0) < venue.submission_cost}
		<Feedback error
			>{venue.submission_cost - charges.reduce((sum, charge) => sum + charge.payment, 0)} more tokens
			to add.</Feedback
		>
	{:else}
		<Note>Verify the balance to enable submission.</Note>

		<Button
			tip="Check if authors have enough tokens"
			active={validChargeFormat(charges) &&
				validCharge(charges, venue.submission_cost) &&
				affordable !== true}
			action={checkAffordability}>Check author balances</Button
		>

		{#if typeof affordable === 'string'}<Feedback error>{affordable}</Feedback>{/if}
	{/if}

	<h3>Submit</h3>

	<Note>Each author will need to approve payment.</Note>

	<Button
		tip="Create a new submission"
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
		}}>Create this submission</Button
	>
</Form>

<style>
	.charge td {
		vertical-align: middle;
	}
</style>
