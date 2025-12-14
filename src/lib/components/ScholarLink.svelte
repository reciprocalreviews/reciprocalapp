<script lang="ts">
	import { type ScholarRow } from '$data/types';
	import { getDB } from '$lib/data/CRUD';
	import Scholar from '$lib/data/Scholar.svelte';
	import { ScholarLabel } from './Labels';
	import Link from './Link.svelte';

	export let id: string | Scholar | ScholarRow;

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
{:else if id instanceof Scholar}
	<div class="scholar">
		<Link to="/scholar/{id.getID()}">{id.getName()}</Link><sub style="text-decoration: none"
			>{ScholarLabel}</sub
		>
	</div>
{:else}
	<Link to="/scholar/{id.id}">{id.name}</Link><sub style="text-decoration: none">{ScholarLabel}</sub
	>
{/if}
