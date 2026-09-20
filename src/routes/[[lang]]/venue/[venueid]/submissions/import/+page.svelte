<script lang="ts">
	import Page from '$lib/components/Page.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import { type PageData } from './$types';
	import BulkImport from './BulkImport.svelte';
	import { getAuth } from '$routes/Auth.svelte';

	let { data }: { data: PageData } = $props();

	let venue = $derived(data.venue);
	let submissionTypes = $derived(data.submissionTypes);
	let existingSubmissions = $derived(data.existingSubmissions);
	let roles = $derived(data.roles);
	let commitments = $derived(data.commitments);

	const auth = getAuth();
	const uid = $derived(auth().getUserID());
	const isAdmin = $derived(uid !== null && venue !== null && venue.admins.includes(uid));
</script>

{#if venue === null || submissionTypes === null || submissionTypes.length === 0}
	<Page band={false} title={(l) => l.page.bulkImport.title}>
		<Feedback error text={(l) => l.page.bulkImport.feedback.notLoaded} />
	</Page>
{:else if !isAdmin}
	<Page band={false} title={(l) => l.page.bulkImport.title}>
		<Feedback error text={(l) => l.page.bulkImport.feedback.notAdmin} />
	</Page>
{:else}
	<Page band={false} title={(l) => l.page.bulkImport.title}>
		<BulkImport {venue} {submissionTypes} {existingSubmissions} {roles} {commitments} />
	</Page>
{/if}
