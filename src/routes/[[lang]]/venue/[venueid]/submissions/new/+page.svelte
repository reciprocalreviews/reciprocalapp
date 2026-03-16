<script lang="ts">
	import NewSubmission from '../NewSubmission.svelte';
	import Page from '$lib/components/Page.svelte';
	import { type PageData } from './$types';
	import Feedback from '$lib/components/Feedback.svelte';
	import { ErrorLabel, SubmissionLabel } from '$lib/components/Labels';

	let { data }: { data: PageData } = $props();

	let venue = $derived(data.venue);
	let submissionTypes = $derived(data.submissionTypes);
</script>

{#if venue === null || submissionTypes === null}
	<Page icon={ErrorLabel} title="New submission" breadcrumbs={[]}>
		<Feedback error text={(l) => l.page.newSubmission.feedback.notLoaded}></Feedback>
	</Page>
{:else}
	<Page
		icon={SubmissionLabel}
		title="New submission"
		breadcrumbs={[
			[`/venue/${venue.id}`, venue.title],
			[`/venue/${venue.id}/submissions`, 'Submissions']
		]}
	>
		<NewSubmission {venue} {submissionTypes}></NewSubmission>
	</Page>
{/if}
