<script lang="ts">
	import { type ScholarRow } from '$data/types';
	import { getDB } from '#lib/data/CRUD.js';
	import Scholar from '#lib/data/Scholar.svelte.js';
	import { ScholarLabel } from './Labels';
	import Link from './Link.svelte';

	let {
		id,
		size = 'normal',
		newTab = false
	}: {
		/** A scholar id to look up, a Scholar already loaded, or just the id and name of
		 * one — the row branch below reads only those two fields, so a caller that already
		 * holds them (a name-search match, an invitation about to be sent) can render
		 * without the round trip and the `...` flash that looking one up costs. */
		id: string | Scholar | Pick<ScholarRow, 'id' | 'name'>;
		size?: 'small' | 'normal' | 'extra-small';
		/** Open the profile in a new tab, so checking who someone is doesn't lose a
		 * choice in progress. */
		newTab?: boolean;
	} = $props();

	const db = getDB();
</script>

{#if typeof id === 'string'}
	{#await db().getScholar(id)}
		...
	{:then scholar}
		{#if scholar}
			<Link {size} {newTab} to="/scholar/{scholar.getID()}" icon={ScholarLabel}
				>{scholar.getName() ?? scholar.getEmail()}</Link
			>
		{:else}
			<em>ORCID {id}</em>
		{/if}
	{:catch}<em>Error {id}</em>{/await}
{:else if id instanceof Scholar}
	<div class="scholar">
		<Link {size} {newTab} to="/scholar/{id.getID()}">{id.getName()}</Link><sub
			class="cling"
			style="text-decoration: none">{ScholarLabel}</sub
		>
	</div>
{:else}
	<Link {size} {newTab} to="/scholar/{id.id}">{id.name}</Link><sub
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
