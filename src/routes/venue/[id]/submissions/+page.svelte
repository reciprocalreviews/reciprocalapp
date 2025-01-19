<script lang="ts">
	import Feedback from '$lib/components/Feedback.svelte';
	import SubmissionPreview from '$lib/components/SubmissionPreview.svelte';
	import Table from '$lib/components/Table.svelte';
	import { getAuth } from '../../../Auth.svelte';
	import { type PageData } from './$types';
	import Page from '$lib/components/Page.svelte';
	import Link from '$lib/components/Link.svelte';
	import Cards from '$lib/components/Cards.svelte';
	import Card from '$lib/components/Card.svelte';
	import NewSubmission from './NewSubmission.svelte';

	let { data }: { data: PageData } = $props();
	const { venue, submissions } = $derived(data);

	const auth = getAuth();
	const uid = $derived(auth.getUserID());
	const editor = $derived(uid !== null && venue !== null && venue.editors.includes(uid));

	const submissionCost = $derived(venue?.submission_cost ?? null);
</script>

{#if venue}
	<Page title={venue.title}>
		{#snippet subtitle()}Submissions{/snippet}
		{#snippet details()}<Link to={venue.url}>{venue.url}</Link>{/snippet}

		<Cards>
			{#if editor && submissionCost !== null}
				<Card
					icon="+"
					header="New submission"
					note="Manually create a new submission"
					group="editors"
					expand
				>
					<NewSubmission venue={venue.id} {submissionCost}></NewSubmission>
				</Card>
			{/if}
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
