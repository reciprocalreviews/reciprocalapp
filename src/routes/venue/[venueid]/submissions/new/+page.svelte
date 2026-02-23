<script lang="ts">
	import NewSubmission from '../NewSubmission.svelte';
	import Page from '$lib/components/Page.svelte';
	import { type PageData } from './$types';
	import Feedback from '$lib/components/Feedback.svelte';

	let { data }: { data: PageData } = $props();

	let venue = $derived(data.venue);
	let submissionTypes = $derived(data.submissionTypes);
</script>

{#if venue === null}
	<Page title="New submission" breadcrumbs={[]}>
		<Feedback error>Venue not found.</Feedback>
	</Page>
{:else}
	<Page
		title="New submission"
		breadcrumbs={[
			[`/venue/${venue.id}`, venue.title],
			[`/venue/${venue.id}/submissions`, 'Submissions']
		]}
	>
		{#if submissionTypes === null}
			<Feedback error>Failed to load submission types.</Feedback>
		{:else}
			<NewSubmission {venue} {submissionTypes}></NewSubmission>
		{/if}
	</Page>
{/if}
