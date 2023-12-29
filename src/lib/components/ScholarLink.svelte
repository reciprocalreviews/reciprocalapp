<script lang="ts">
	import { getDB } from '$lib/Context';
	import type Scholar from '$lib/types/Scholar';
	import type { ScholarID } from '$lib/types/Scholar';
	import Link from './Link.svelte';

	export let id: ScholarID | Scholar;

	const db = getDB();
</script>

{#if typeof id === 'string'}
	{#await db.getScholar(id)}
		...
	{:then scholar}
		{#if scholar}
			<Link to="/scholar/{scholar.id}">{scholar.name}</Link>
		{:else}
			<em>ORCID {id}</em>
		{/if}
	{:catch}<em>Error {id}</em>{/await}
{:else}
	<Link to="/scholar/{id.id}">{id.name}</Link>
{/if}
