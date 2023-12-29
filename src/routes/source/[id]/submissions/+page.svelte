<script lang="ts">
	import { page } from '$app/stores';
	import { getAuth, getDB } from '$lib/Context';
	import Button from '$lib/components/Button.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import Form from '$lib/components/Form.svelte';
	import Loading from '$lib/components/Loading.svelte';
	import Note from '$lib/components/Note.svelte';
	import ScholarLink from '$lib/components/ScholarLink.svelte';
	import SubmissionPreview from '$lib/components/SubmissionPreview.svelte';
	import Table from '$lib/components/Table.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import Tokens from '$lib/components/Tokens.svelte';
	import createSubmission from '$lib/data/createSubmission';
	import { ORCIDRegex } from '$lib/types/Scholar';
	import type Submission from '$lib/types/Submission';

	const db = getDB();
	const auth = getAuth();

	/** The promise we're currently waiting for */
	let sourcePromise = db.getSource($page.params.id);
	let submissionsPromise = db.getActiveSubmissions($page.params.id);

	/** The title of the submission we're adding */
	let title = '';
	let externalID = '';
	let metaID = '';
	let charges = '';

	function validTitle(title: string) {
		return title.length > 0;
	}

	function validExternalID(id: string) {
		return id.length > 0;
	}

	function validMeta(id: string) {
		return id.length === 0 || ORCIDRegex.test(id);
	}

	function validCharges(text: string, cost: number) {
		return cost === 0 || (validChargeFormat(text) && validCharge(text, cost));
	}

	function validChargeFormat(text: string) {
		return text.split('\n').every((line) => {
			const parts = line.trim().split(' ');
			return parts.length === 2 && ORCIDRegex.test(parts[0]) && !isNaN(parseFloat(parts[1]));
		});
	}

	function validCharge(text: string, cost: number) {
		return text.split('\n').reduce((sum, line) => sum + parseFloat(line.split(' ')[1]), 0) === cost;
	}

	function chargeTextToCharges(text: string): { scholar: string; payment: number }[] {
		return text.split('\n').map((line) => {
			const parts = line.split(' ');
			return { scholar: parts[0], payment: parseFloat(parts[1]) };
		});
	}

	function validSubmission(
		title: string,
		externalID: string,
		metaID: string,
		charges: string,
		cost: number
	) {
		return (
			validTitle(title) &&
			validExternalID(externalID) &&
			validMeta(metaID) &&
			validCharges(charges, cost)
		);
	}

	async function charge(cost: number) {
		if (!validSubmission(title, externalID, metaID, charges, cost)) return;
		if ($auth === null) return;

		// Create the submission.
		await createSubmission(
			db,
			$page.params.id,
			$auth?.getScholarID(),
			title,
			externalID,
			metaID,
			chargeTextToCharges(charges)
		);
		// Update the submissions
		submissionsPromise = db.getActiveSubmissions($page.params.id);
	}
</script>

<h1>Submissions</h1>
{#await sourcePromise}
	<Loading />
{:then source}
	{@const editor = $auth && source.editors.includes($auth.getScholarID())}
	{#if editor}
		<h2>New</h2>

		<p>
			When you create a new submission, authors will be charged the number of tokens you specify.
		</p>

		<p>
			<Form>
				<TextField size={40} placeholder="Submission Title" bind:text={title} valid={validTitle} />
				<Note>For display on this site.</Note>
				<TextField
					size={40}
					placeholder="Manuscript ID"
					bind:text={externalID}
					valid={validExternalID}
				/>
				<Note>The ID from the system where the submission is stored, for reference.</Note>
				<TextField
					type="box"
					size={40}
					placeholder="Charges, e.g., '0000-0001-1234-5678 3'"
					bind:text={charges}
					valid={(text) => validCharges(text, source.cost.submit)}
				/>
				{#if charges.length > 0}
					{#if !validChargeFormat(charges)}
						<Feedback error>Each line must be an ORCID, then a space, then a number.</Feedback>
					{:else if !validCharge(charges, source.cost.submit)}
						<Feedback error
							>The charges do not sum to <Tokens amount={source.cost.submit} />.</Feedback
						>
					{:else if charges.length > 0}
						{#await db.verifyCharges(chargeTextToCharges(charges)) then result}
							{#if result !== true}
								<Feedback error
									>The scholars specified don't have enough tokens to submit. {#each result.filter((result) => result.payment < 0) as deficit}<ScholarLink
											id={deficit.scholar}
										/> is short <Tokens amount={Math.abs(deficit.payment)} />{/each}</Feedback
								>
							{/if}
						{/await}
					{/if}
				{/if}

				<Note
					>Who to charge and how many review tokens to charge. Each line should be an ORCID, then a
					space, then a token count. Tokens should sum to the number required for submission.</Note
				>
				<TextField
					size={40}
					placeholder="Metareviewer ORCID"
					bind:text={metaID}
					valid={validMeta}
				/>
				<Note
					><strong>Optional</strong>. The ORCID of the scholar serving as the meta-reviewer for this
					submission, if there is one.</Note
				>
				{#if metaID.length > 0 && !validMeta(metaID)}
					<Feedback error>This is not a valid ORCID.</Feedback>
				{/if}
				<Button
					active={validSubmission(title, externalID, metaID, charges, source.cost.submit)}
					action={() => charge(source.cost.submit)}>Create submission and charge authors</Button
				>
			</Form>
		</p>

		<h2>In Review</h2>
		<p>
			These are submissions actively being reviewed. When a submissions is done being reviewed, go
			to it's page to mark it complete to compensate everyone.
		</p>
		{#await submissionsPromise}
			<Loading />
		{:then submissions}
			<Table>
				{#each submissions as submission}
					<tr>
						<td><SubmissionPreview {submission} /></td><td>{submission.externalID}</td>
					</tr>
				{:else}
					<Feedback>No active submissions.</Feedback>
				{/each}
			</Table>
		{:catch}
			<Feedback error>We couldn't load this source's submissions.</Feedback>
		{/await}
	{:else}
		<Feedback error>
			Submissions are only visible to <strong>editors</strong>.
		</Feedback>
	{/if}
{:catch}
	<h1>Unknown Source</h1>
	<Feedback>We couldn't load this source.</Feedback>
{/await}
