<!-- This Source Code Form is subject to the terms of the Mozilla Public
  -- License, v. 2.0. If a copy of the MPL was not distributed with this
  -- file, You can obtain one at http://mozilla.org/MPL/2.0/.
  -->

<script lang="ts">
	import { page } from '$app/stores';
	import Button from '$lib/components/Button.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import Form from '$lib/components/Form.svelte';
	import Loading from '$lib/components/Loading.svelte';
	import ScholarLink from '$lib/components/ScholarLink.svelte';
	import SourceLink from '$lib/components/SourceLink.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import TransactionPreview from '$lib/components/TransactionPreview.svelte';
	import { getAuth, getDB } from '$lib/Context';
	import closeSubmission from '$lib/data/archiveSubmission';
	import { ORCIDRegex } from '$lib/types/Scholar';
	import type Submission from '$lib/types/Submission';

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
		await closeSubmission(db, submission.id, toReviewers(reviewers));
		submissionPromise = db.getSubmission($page.params.id);
	}
</script>

{#if $auth === null}
	<h1>Submission</h1>
	<Feedback error>Log in to view submissions.</Feedback>
{:else}
	{#await submissionPromise}
		<h1>Submission</h1>
		<Loading />
	{:then submission}
		{@const editor = $auth !== null && submission.editorID === $auth.getScholarID()}
		{#if editor}
			<h1>{submission.title}</h1>
			<p><SourceLink id={submission.sourceID} /></p>
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
						bind:text={reviewers}
						size={50}
						valid={(text) => validReviewers(text)}
						placeholder="Reviewer ORCIDs separated by commas"
					/>
					{#if validReviewers(reviewers)}
						{#each toReviewers(reviewers) as reviewer}
							<ScholarLink id={reviewer} />
						{/each}
					{/if}
					<Button action={() => done(submission)} active={validReviewers(reviewers)}
						>Compensate</Button
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
