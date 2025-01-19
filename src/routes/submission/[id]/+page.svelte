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

	let { data }: { data: PageData } = $props();
	const { submission, venue, authors } = $derived(data);

	const db = getDB();
	const auth = getAuth();
	const user = $derived(auth.getUserID());

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
	>
		{#snippet subtitle()}Submission{/snippet}
		{#snippet details()}
			{#if submission.previousid}{submission.previousid} →
			{/if}{submission.externalid}
		{/snippet}

		<h2>Authors</h2>

		{#if authors}
			{#each submission.authors as author}
				{@const authorIndex = authors.findIndex((a) => a.id === author)}
				{@const payment = authorIndex !== undefined ? submission.payments[authorIndex] : undefined}
				<Row>
					{#if authorIndex === undefined}
						<Feedback error>Unable to find authors.</Feedback>
					{:else}
						<ScholarLink id={author}></ScholarLink>
						{#if payment !== undefined}
							paid <Tokens amount={payment} />{/if}
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
