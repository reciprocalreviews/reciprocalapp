<script lang="ts">
	import Page from '$lib/components/Page.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import { ErrorLabel, SubmissionLabel } from '$lib/components/Labels';
	import { type PageData } from './$types';
	import BulkImport from './BulkImport.svelte';
	import { getAuth } from '$routes/Auth.svelte';

	let { data }: { data: PageData } = $props();

	let venue = $derived(data.venue);
	let submissionTypes = $derived(data.submissionTypes);
	let existingExternalIDs = $derived(data.existingExternalIDs);

	const auth = getAuth();
	const uid = $derived(auth().getUserID());
	const isAdmin = $derived(uid !== null && venue !== null && venue.admins.includes(uid));
</script>

{#if venue === null || submissionTypes === null || submissionTypes.length === 0}
	<Page icon={ErrorLabel} title={(l) => l.page.bulkImport.title} breadcrumbs={[]}>
		<Feedback error text={(l) => l.page.bulkImport.feedback.notLoaded} />
	</Page>
{:else if !isAdmin}
	<Page
		icon={ErrorLabel}
		title={(l) => l.page.bulkImport.title}
		breadcrumbs={[
			[`/venue/${venue.id}`, venue.title],
			[`/venue/${venue.id}/submissions`, 'Submissions']
		]}
	>
		<Feedback error text={(l) => l.page.bulkImport.feedback.notAdmin} />
	</Page>
{:else}
	<Page
		icon={SubmissionLabel}
		title={(l) => l.page.bulkImport.title}
		breadcrumbs={[
			[`/venue/${venue.id}`, venue.title],
			[`/venue/${venue.id}/submissions`, 'Submissions']
		]}
	>
		<BulkImport {venue} {submissionTypes} {existingExternalIDs} />
	</Page>
{/if}
