<script lang="ts">
	import { page } from '$app/stores';
	import Button from '$lib/components/Button.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import Form from '$lib/components/Form.svelte';
	import Loading from '$lib/components/Loading.svelte';
	import ScholarLink from '$lib/components/ScholarLink.svelte';
	import SourceLink from '$lib/components/VenueLink.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import TransactionPreview from '$lib/components/TransactionPreview.svelte';
	import { getDB } from '$lib/data/CRUD';
	import { ORCIDRegex } from '../../../data/ORCID';
	import type Submission from '$lib/types/Submission';
	import { getAuth } from '../../Auth.svelte';

	const db = getDB();
	const auth = getAuth();

	let submissionPromise = db.getSubmission($page.params.id);

	/** The list of reviewers to compensate */
	let reviewers = '';

	function validReviewers(text: string) {
		return toReviewers(text).every((reviewer) => ORCIDRegex.test(reviewer));
	}

	function toReviewers(text: string) {
		return text.split(',').map((reviewer) => reviewer.trim());
	}

	async function done(submission: Submission) {
		// await closeSubmission(db, submission.id, toReviewers(reviewers));
		submissionPromise = db.getSubmission($page.params.id);
	}
</script>

{#if !auth.isAuthenticated()}
	<h1>Submission</h1>
	<Feedback error>Log in to view submissions.</Feedback>
{:else}
	{#await submissionPromise}
		<h1>Submission</h1>
		<Loading />
	{:then submission}
		{@const editor = submission.editorID === auth.getUserID()}
		{#if editor}
			<h1>{submission.title}</h1>
			<p><SourceLink id={submission.sourceID} name="" /></p>
			<h2>Editor</h2>
			<p><ScholarLink id={submission.editorID} /></p>

			<h2>Meta-Reviewer</h2>
			<p><ScholarLink id={submission.metaID} /></p>

			<h2>Charges</h2>
			{#each submission.charges as transactionID}
				<TransactionPreview id={transactionID} />
			{/each}

			<h2>Payments</h2>
			{#if submission.payment}
				<Feedback>This submission is archived.</Feedback>
				{#each submission.payment as transactionID}
					<TransactionPreview id={transactionID} />
				{/each}
			{:else}
				<p>
					Is review complete for this submission? Enter the reviewers who should receive
					compensation, then they, the meta-reviewer, and editor above will be compensated, and this
					submission will be archived.
				</p>
				<Form>
					<TextField
						label="ORCIDs"
						placeholder="Reviewer ORCIDs separated by commas"
						bind:text={reviewers}
						size={50}
						valid={(text) => validReviewers(text)}
					/>
					{#if validReviewers(reviewers)}
						{#each toReviewers(reviewers) as reviewer}
							<ScholarLink id={reviewer} />
						{/each}
					{/if}
					<Button
						tip="Compensate"
						action={() => done(submission)}
						active={validReviewers(reviewers)}>Compensate</Button
					>
				</Form>
			{/if}
		{:else}
			<Feedback error>Submissions can only be viewed editors.</Feedback>
		{/if}
	{:catch}
		<h1>Unknown submission</h1>
		<Feedback>We couldn't load this source.</Feedback>
	{/await}
{/if}
