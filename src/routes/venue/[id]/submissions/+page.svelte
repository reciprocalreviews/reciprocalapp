<script lang="ts">
	import { getDB } from '$lib/data/CRUD';
	import Button from '$lib/components/Button.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import Form from '$lib/components/Form.svelte';
	import Note from '$lib/components/Note.svelte';
	import ScholarLink from '$lib/components/ScholarLink.svelte';
	import SubmissionPreview from '$lib/components/SubmissionPreview.svelte';
	import Table from '$lib/components/Table.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import Tokens from '$lib/components/Tokens.svelte';
	import { ORCIDRegex } from '$lib/data/ORCID';
	import { getAuth } from '../../../Auth.svelte';
	import { isntEmpty } from '$lib/validation';
	import { type PageData } from './$types';
	import Page from '$lib/components/Page.svelte';
	import Link from '$lib/components/Link.svelte';
	import Cards from '$lib/components/Cards.svelte';
	import Card from '$lib/components/Card.svelte';

	let { data }: { data: PageData } = $props();
	const { venue, submissions } = $derived(data);

	const db = getDB();
	const auth = getAuth();
	const uid = $derived(auth.getUserID());
	const editor = $derived(uid !== null && venue !== null && venue.editors.includes(uid));

	const submissionCost = $derived(venue?.submission_cost ?? null);

	/** The title of the submission we're adding */
	let title = $state('');
	let externalID = $state('');
	let metaID = $state('');
	let charges = $state('');

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
			isntEmpty(title) &&
			validExternalID(externalID) &&
			validMeta(metaID) &&
			validCharges(charges, cost)
		);
	}
</script>

{#if venue}
	<Page title={venue.title}>
		{#snippet subtitle()}Submissions{/snippet}
		{#snippet details()}<Link to={venue.url}>{venue.url}</Link>{/snippet}

		<Cards>
			<Card icon="+" header="New submission" note="Create a new submission" group="editors">
				{#if editor && submissionCost !== null}
					<p>
						When you create a new submission, authors will be charged the number of tokens you
						specify.
					</p>

					<p>
						<Form>
							<TextField
								label="title"
								size={40}
								placeholder="Submission Title"
								bind:text={title}
								valid={(text) => (isntEmpty(text) ? undefined : 'Title must be non-empty.')}
								note="For display on this site."
							/>
							<TextField
								label="id"
								size={40}
								placeholder="Manuscript ID"
								bind:text={externalID}
								valid={(text) => (validExternalID(text) ? undefined : 'ID must be non-empty.')}
								note="The ID from the system where the submission is stored, for reference."
							/>
							<TextField
								label="id"
								inline={false}
								size={40}
								placeholder="Charges, e.g., '0000-0001-1234-5678 3'"
								bind:text={charges}
								valid={(text) =>
									validCharges(text, submissionCost)
										? undefined
										: 'Charges must sum to the submission cost.'}
							/>
							{#if charges.length > 0}
								{#if !validChargeFormat(charges)}
									<Feedback error>Each line must be an ORCID, then a space, then a number.</Feedback
									>
								{:else if !validCharge(charges, submissionCost)}
									<Feedback error
										>The charges do not sum to <Tokens amount={submissionCost} />.</Feedback
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
								>Who to charge and how many review tokens to charge. Each line should be an ORCID,
								then a space, then a token count. Tokens should sum to the number required for
								submission.</Note
							>
							<TextField
								label="Metareviewer"
								size={40}
								placeholder="Metareviewer ORCID"
								bind:text={metaID}
								valid={(text) => (validMeta(text) ? undefined : 'Invalid ORCID.')}
							/>
							<Note
								><strong>Optional</strong>. The ORCID of the scholar serving as the meta-reviewer
								for this submission, if there is one.</Note
							>
							{#if metaID.length > 0 && !validMeta(metaID)}
								<Feedback error>This is not a valid ORCID.</Feedback>
							{/if}
							<Button
								tip="Create a new submission"
								active={validSubmission(title, externalID, metaID, charges, submissionCost)}
								action={() => {}}>Create submission and charge authors</Button
							>
						</Form>
					</p>
				{:else}
					<Feedback error>
						Submissions are only visible to <strong>editors</strong>.
					</Feedback>
				{/if}
			</Card>
		</Cards>

		{#if submissions}
			{#if submissions.length === 0}
				<Feedback>No active submissions.</Feedback>
			{:else}
				<Table>
					{#each submissions as submission}
						<tr>
							<td><SubmissionPreview {submission} /></td><td>{submission.externalid}</td>
						</tr>
					{:else}
						<Feedback>No active submissions.</Feedback>
					{/each}
				</Table>
			{/if}
		{:else}
			<Feedback error>Unable to load submissions.</Feedback>
		{/if}
	</Page>
{/if}
