<script lang="ts">
	import type { Snippet } from 'svelte';
	import type { LayoutData } from './$types';
	import Page from '$lib/components/Page.svelte';

	let { data, children }: { data: LayoutData; children: Snippet } = $props();
	const { venue } = $derived(data);
</script>

{#if venue === null}
	<Page title="Unknown venue" breadcrumbs={[[`/venues`, 'Venue']]}>
		<p>Unable to find this venue.</p>
	</Page>
{:else}
	{@render children()}
{/if}
