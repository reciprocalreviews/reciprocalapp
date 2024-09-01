<script lang="ts">
	import Feedback from '$lib/components/Feedback.svelte';
	import Scholar from './Scholar.svelte';

	export let data;

	$: scholar = data.scholar;
</script>

{#if scholar}
	<Scholar {scholar} />
{:else}
	<h1>Oops.</h1>
	<Feedback error>Unable to find scholar.</Feedback>
{/if}
