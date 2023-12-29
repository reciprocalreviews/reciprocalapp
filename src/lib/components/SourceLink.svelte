<script lang="ts">
	import { getDB } from '$lib/Context';
	import Link from './Link.svelte';

	export let id: string;

	const db = getDB();
</script>

{#await db.getSource(id)}
	...
{:then source}
	<Link to="/source/{source.id}">{source.name}</Link>{:catch}?{/await}
