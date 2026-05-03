<script lang="ts">
	import { type ScholarRow } from '$data/types';
	import { getDB } from '$lib/data/CRUD';
	import Scholar from '$lib/data/Scholar.svelte';
	import { ScholarLabel } from './Labels';
	import Link from './Link.svelte';

	let {
		id,
		size = 'normal'
	}: {
		id: string | Scholar | ScholarRow;
		size?: 'small' | 'normal' | 'extra-small';
	} = $props();

	const db = getDB();
</script>

{#if typeof id === 'string'}
	{#await db().getScholar(id)}
		...
	{:then scholar}
		{#if scholar}
			<Link {size} to="/scholar/{scholar.getID()}" icon={ScholarLabel}
				>{scholar.getName() ?? scholar.getEmail()}</Link
			>
		{:else}
			<em>ORCID {id}</em>
		{/if}
	{:catch}<em>Error {id}</em>{/await}
{:else if id instanceof Scholar}
	<div class="scholar">
		<Link {size} to="/scholar/{id.getID()}">{id.getName()}</Link><sub
			class="cling"
			style="text-decoration: none">{ScholarLabel}</sub
		>
	</div>
{:else}
	<Link {size} to="/scholar/{id.id}">{id.name}</Link><sub
		class="cling"
		style="text-decoration: none">{ScholarLabel}</sub
	>
{/if}

<style>
	/* Same Word Joiner trick as Link.svelte for subs that live outside the
	   anchor (e.g., the Scholar/ScholarRow branches above). */
	.cling::before {
		content: '\2060';
	}
</style>
