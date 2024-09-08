<script lang="ts">
	import Feedback from '$lib/components/Feedback.svelte';
	import { getDB } from '$lib/data/Database';
	import type { ScholarRow } from '../../../data/types';
	import { default as ScholarView } from './Scholar.svelte';

	let { data }: { data: { scholar: ScholarRow | null } } = $props();

	let db = getDB();

	/** Register a scholar state. */
	let state = data.scholar ? db.registerScholar(data.scholar) : null;
</script>

{#if state}
	<ScholarView scholar={state} />
{:else}
	<h1>Oops.</h1>
	<Feedback error>Unknown scholar.</Feedback>
{/if}
