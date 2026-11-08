<script lang="ts">
	import Page from '#lib/components/Page.svelte';
	import { venueBarName } from '#lib/data/venueBarLinks.js';
	import Feedback from '#lib/components/Feedback.svelte';
	import { type PageData } from './$types';
	import BulkImport from './BulkImport.svelte';

	let { data }: { data: PageData } = $props();

	let venue = $derived(data.venue);
	let submissionTypes = $derived(data.submissionTypes);
	let existingSubmissions = $derived(data.existingSubmissions);
	let roles = $derived(data.roles);
	let commitments = $derived(data.commitments);
	let mayImport = $derived(data.mayImport);
</script>

{#if venue === null || submissionTypes === null || submissionTypes.length === 0}
	<Page title={(l) => l.page.bulkImport.title}>
		<Feedback error text={(l) => l.page.bulkImport.feedback.notLoaded} />
	</Page>
{:else if !mayImport}
	<Page title={(l) => l.page.bulkImport.title}>
		<Feedback error text={(l) => l.page.bulkImport.feedback.notAdmin} />
	</Page>
{:else}
	<Page title={(l) => l.page.bulkImport.title} context={venueBarName(venue)}>
		<BulkImport {venue} {submissionTypes} {existingSubmissions} {roles} {commitments} />
	</Page>
{/if}
