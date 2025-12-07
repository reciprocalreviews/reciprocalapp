<script lang="ts">
	import { getDB } from '$lib/data/CRUD';
	import Scholar from '$lib/data/Scholar.svelte';
	import { ScholarLabel } from './Labels';
	import Link from './Link.svelte';

	export let id: string | Scholar;

	const db = getDB();
</script>

{#if typeof id === 'string'}
	{#await db().getScholar(id)}
		...
	{:then scholar}
		{#if scholar}
			<Link to="/scholar/{scholar.getID()}" icon={ScholarLabel}
				>{scholar.getName() ?? scholar.getEmail()}</Link
			>
		{:else}
			<em>ORCID {id}</em>
		{/if}
	{:catch}<em>Error {id}</em>{/await}
{:else}
	<div class="scholar">
		<Link to="/scholar/{id.getID()}">{id.getName()}</Link><sub style="text-decoration: none"
			>{ScholarLabel}</sub
		>
	</div>
{/if}
