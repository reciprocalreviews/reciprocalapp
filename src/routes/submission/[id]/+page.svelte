<script lang="ts">
	import Feedback from '$lib/components/Feedback.svelte';
	import { type PageData } from './$types';
	import Page from '$lib/components/Page.svelte';
	import VenueLink from '$lib/components/VenueLink.svelte';
	import ScholarLink from '$lib/components/ScholarLink.svelte';
	import Tokens from '$lib/components/Tokens.svelte';
	import Row from '$lib/components/Row.svelte';
	import EditableText from '$lib/components/EditableText.svelte';
	import { getDB } from '$lib/data/CRUD';
	import { getAuth } from '../../Auth.svelte';
	import Link from '$lib/components/Link.svelte';
	import Status from '$lib/components/Status.svelte';
	import Checkbox from '$lib/components/Checkbox.svelte';

	let { data }: { data: PageData } = $props();
	const { submission, venue, authors, previous, transactions } = $derived(data);

	const db = getDB();
	const auth = getAuth();
	const user = $derived(auth.getUserID());
	const authorTransactions = $derived(
		submission === null || transactions === null
			? null
			: submission.transactions.map((id) => transactions.find((t) => t.id === id))
	);

	let isEditor = $derived(venue !== null && user !== null && venue.editors.includes(user));

	let isAuthor = $derived(
		submission !== null && user !== null && submission.authors.includes(user)
	);
</script>

{#if submission === null}
	<Page title="Submission" breadcrumbs={[]}>
		<Feedback error>This submission does not exist.</Feedback>
	</Page>
{:else if !isEditor && !isAuthor}
	<Page title="Submission" breadcrumbs={[]}>
		<Feedback error>You are not authorized to view this submission.</Feedback>
	</Page>
{:else}
	<Page
		title={submission.title}
		breadcrumbs={[[`/venue/${submission.venue}/submissions`, 'Submissions']]}
		edit={isAuthor || isEditor
			? {
					placeholder: 'Title',
					valid: (text) => (text.trim().length === 0 ? 'Title cannot be empty.' : undefined),
					update: (text) => db.updateSubmissionTitle(submission.id, text)
				}
			: undefined}
	>
		{#snippet subtitle()}Submission{/snippet}
		{#snippet details()}
			{#if submission.status === 'reviewing'}<Status>reviewing</Status>{:else}<Status good={false}
					>done</Status
				>{/if}
			{#if previous}<Link to="/submission/{previous.id}">{previous.externalid}</Link>
				→{/if}
			{submission.externalid}
		{/snippet}

		{#if isEditor}
			<Checkbox
				on={submission.status === 'reviewing'}
				change={(on) => db.updateSubmissionStatus(submission.id, on ? 'reviewing' : 'done')}
				>This submission is still in review.</Checkbox
			>
		{/if}

		<h2>Authors</h2>

		{#if authors}
			{#each submission.authors as author}
				{@const authorIndex = authors.findIndex((a) => a.id === author)}
				{@const payment = authorIndex !== undefined ? submission.payments[authorIndex] : undefined}
				{@const transaction =
					authorTransactions === null || authorIndex === undefined
						? undefined
						: authorTransactions[authorIndex]}
				<Row>
					{#if authorIndex === undefined}
						<Feedback error>Unable to find authors.</Feedback>
					{:else}
						<ScholarLink id={author}></ScholarLink>
						{#if (isEditor || isAuthor) && payment !== undefined}
							{#if transaction === undefined}
								<Status good={false}>unknown transaction</Status>
							{:else}
								{#if transaction.status === 'proposed'}
									proposes to pay
								{:else if transaction.status === 'approved'}
									paid
								{:else if transaction.status === 'canceled'}
									declined to pay
								{/if}
								<Tokens amount={payment} />
							{/if}
						{/if}
					{/if}
				</Row>
			{/each}
		{:else}{/if}

		<h2>Venue</h2>
		{#if venue}
			<VenueLink id={venue.id} name={venue.title} />
		{/if}

		<h2>Expertise</h2>
		{#if isAuthor}
			<EditableText
				text={submission.expertise ?? ''}
				placeholder="Expertise"
				edit={(text) =>
					db.updateSubmissionExpertise(submission.id, text.trim().length === 0 ? null : text)}
			/>
		{:else if submission.expertise}{submission.expertise}{:else}<Feedback
				>No expertise provided</Feedback
			>{/if}
	</Page>
{/if}
