<script lang="ts">
	import { getDB } from '$lib/data/CRUD';
	import Link from './Link.svelte';

	interface Props {
		id: string;
		name?: string;
	}

	let { id, name }: Props = $props();

	const db = getDB();
</script>

{#snippet link(id: string, name: string)}
	<Link to="/venue/{id}">{name}</Link>
{/snippet}

{#if name === undefined}
	{#await db.getSource(id)}
		...
	{:then source}
		{@render link(id, source.name)}
	{:catch}
		?
	{/await}
{:else}
	{@render link(id, name)}
{/if}
