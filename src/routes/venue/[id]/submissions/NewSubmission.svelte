<script lang="ts">
	import type { VenueID } from '$data/types';
	import Button from '$lib/components/Button.svelte';
	import Form from '$lib/components/Form.svelte';
	import Note from '$lib/components/Note.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import Tip from '$lib/components/Tip.svelte';
	import { getDB } from '$lib/data/CRUD';
	import { ORCIDRegex } from '$lib/data/ORCID';
	import { isntEmpty } from '$lib/validation';
	import { getAuth } from '../../../Auth.svelte';
	import { handle } from '../../../feedback.svelte';

	let {
		venue,
		submissionCost,
		/** @ts-ignore Whether the form is expanded. Useful for parent components to set and get state. */
		expanded = $bindable(true)
	}: { venue: VenueID; submissionCost: number; expanded: boolean } = $props();

	const db = getDB();
	const auth = getAuth();
	const user = $derived(auth.getUserID());

	/** The title of the submission we're adding */
	let title = $state('');
	let expertise = $state('');
	let externalID = $state('');
	let previousID = $state('');
	let charges = $state('');

	/** True if the specified charges can be afforded, undefined if checking, string describing the problem. */
	let affordable = $state<string | undefined | true>(undefined);

	/** When charges change, reset affordable */
	$effect(() => {
		if (charges) affordable = undefined;
	});

	function validExternalID(id: string) {
		return id.length > 0;
	}

	function validCharges(text: string, cost: number) {
		return cost === 0 || (validChargeFormat(text) && validCharge(text, cost));
	}

	function validChargeFormat(text: string) {
		return (
			text.length === 0 ||
			text.split('\n').every((line) => {
				const parts = line.trim().split(' ');
				return parts.length === 2 && ORCIDRegex.test(parts[0]) && !isNaN(parseFloat(parts[1]));
			})
		);
	}

	function duplicateScholars(text: string) {
		const lines = text.split('\n');
		return new Set(lines.map((line) => line.trim().split(' ')[0])).size !== lines.length;
	}

	function validCharge(text: string, cost: number) {
		return (
			text.trim().length === 0 ||
			text.split('\n').reduce((sum, line) => sum + parseFloat(line.split(' ')[1]), 0) === cost
		);
	}

	function chargeTextToCharges(text: string): { scholar: string; payment: number }[] {
		return text.trim().length === 0
			? []
			: text.split('\n').map((line) => {
					const parts = line.split(' ');
					return { scholar: parts[0], payment: parseFloat(parts[1]) };
				});
	}

	async function checkAffordability() {
		affordable = undefined;
		const result = await db.verifyCharges(chargeTextToCharges(charges));
		if (result === undefined) {
			affordable = 'An error occurred while checking balances.';
		} else if (result !== true) {
			affordable =
				'There are not enough tokens to submit: ' +
				result
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

	function validSubmission(title: string, externalID: string, charges: string, cost: number) {
		return (
			isntEmpty(title) &&
			validExternalID(externalID) &&
			(previousID.length === 0 || validExternalID(previousID)) &&
			validCharges(charges, cost)
		);
	}
</script>

<p>When you create a new submission, authors will be charged the number of tokens you specify.</p>

<Tip>Set up email integrations to automate submission creation.</Tip>

<Form>
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
		note="For bidding, if enabled."
	/>
	<TextField
		label="manuscript id"
		size={40}
		placeholder="id"
		bind:text={externalID}
		valid={(text) => (validExternalID(text) ? undefined : 'ID must be non-empty.')}
		note="The ID from the review system, for reference."
	/>
	<TextField
		label="previous manuscript id"
		size={40}
		placeholder="id"
		bind:text={previousID}
		note="The ID of the previous submission, if this is a revision and you want to track it."
	/>
	<TextField
		label="payment"
		inline={false}
		size={40}
		placeholder="0000-0001-1234-5678 3..."
		bind:text={charges}
		valid={() =>
			affordable === true
				? undefined
				: charges.length === 0 && submissionCost > 0
					? 'You must specify charges for the submission.'
					: !validChargeFormat(charges)
						? 'Each line must be an ORCID, then a space, then a number.'
						: duplicateScholars(charges)
							? 'Scholars must be unique.'
							: !validCharge(charges, submissionCost)
								? `The charges do not sum to the submission cost of ${submissionCost}`
								: affordable === undefined
									? "When you're done, check balances below."
									: affordable}
		note={affordable === true
			? 'These authors can afford this charge.'
			: `By line, authors and how many tokens to charge each of them. Tokens must sum to ${submissionCost}.`}
	/>
	<Button
		tip="Check if authors have enough tokens"
		active={validChargeFormat(charges) &&
			validCharge(charges, submissionCost) &&
			affordable !== true}
		action={checkAffordability}>Check author balances</Button
	>

	<Button
		tip="Create a new submission"
		active={affordable === true && validSubmission(title, externalID, charges, submissionCost)}
		action={async () => {
			if (user) {
				const result = await handle(
					db.createSubmission(
						user,
						title,
						expertise,
						venue,
						externalID,
						previousID,
						chargeTextToCharges(charges)
					)
				);

				// Reset form if successful.
				if (result) {
					title = '';
					expertise = '';
					externalID = '';
					previousID = '';
					charges = '';
					affordable = undefined;
					expanded = false;
				}

				return result;
			}
		}}>Create this submission</Button
	>
	<Note>Authors will still need to approve charges.</Note>
</Form>
