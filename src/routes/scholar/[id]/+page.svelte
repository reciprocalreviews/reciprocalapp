<script lang="ts">
	import Feedback from '$lib/components/Feedback.svelte';
	import { getDB } from '$lib/data/CRUD';
	import { default as ScholarView } from './Scholar.svelte';
	import Page from '$lib/components/Page.svelte';

	let { data } = $props();

	let { commitments, venues } = $derived(data);

	let volunteering = $derived(
		commitments
			?.map((c) => {
				return {
					name: c.roles?.name,
					venue: venues?.find((v) => v.id === c.roles?.venueid)?.title
				};
			})
			.filter(
				(v): v is { name: string; venue: string } => v.name !== undefined && v.venue !== undefined
			) ?? []
	);

	let db = getDB();

	/** Register a scholar state. */
	let state = data.scholar ? db.registerScholar(data.scholar) : null;
</script>

{#if state}
	<Page title={state.getName() ?? 'anonymous'} subtitle="Scholar">
		<ScholarView scholar={state} commitments={volunteering} />
	</Page>
{:else}
	<h1>Oops.</h1>
	<Feedback error>Unknown scholar.</Feedback>
{/if}
