<script lang="ts">
	import Feedback from '$lib/components/Feedback.svelte';
	import { getDB } from '$lib/data/CRUD';
	import { default as ScholarView } from './Scholar.svelte';
	import Page from '$lib/components/Page.svelte';

	let { data } = $props();

	let db = getDB();

	/** Register a scholar state. */
	let state = data.scholar ? db.registerScholar(data.scholar) : null;
</script>

{#if state}
	<Page title={state.getName() ?? 'anonymous'} subtitle="Scholar">
		<ScholarView scholar={state} />
	</Page>
{:else}
	<h1>Oops.</h1>
	<Feedback error>Unknown scholar.</Feedback>
{/if}
