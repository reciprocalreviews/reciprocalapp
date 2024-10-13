<script lang="ts">
	import { getDB } from '$lib/data/CRUD';
	import type Scholar from '$lib/data/Scholar.svelte';
	import Link from './Link.svelte';

	export let id: string | Scholar;

	const db = getDB();
</script>

{#if typeof id === 'string'}
	{#await db.getScholar(id)}
		...
	{:then scholar}
		{#if scholar}
			<Link to="/scholar/{scholar.getID()}">{scholar.getName()}</Link>
		{:else}
			<em>ORCID {id}</em>
		{/if}
	{:catch}<em>Error {id}</em>{/await}
{:else}
	<Link to="/scholar/{id.getID()}">{id.getName()}</Link>
{/if}
