<script lang="ts">
	import { page } from '$app/stores';
	import Feedback from '$lib/components/Feedback.svelte';
	import Scholar from '$lib/components/Scholar.svelte';
	import { getDB } from '$lib/Context';

	const db = getDB();
</script>

<!-- If this is the logged in scholar, show their info -->
{#await db.getScholar($page.params.id) then scholar}
	{#if scholar !== null}
		<Scholar {scholar} />
	{:else}
		<Feedback error>There's no account associated with this ORCID here.</Feedback>
	{/if}
{:catch}
	<h1>Scholar {$page.params.id}</h1>
	<Feedback>We couldn't load this scholar.</Feedback>
{/await}
