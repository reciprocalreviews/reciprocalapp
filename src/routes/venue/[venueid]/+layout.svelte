<script lang="ts">
	import type { Snippet } from 'svelte';
	import type { LayoutData } from './$types';
	import Page from '$lib/components/Page.svelte';
	import Note from '$lib/components/Note.svelte';
	import Link from '$lib/components/Link.svelte';
	import ScholarLink from '$lib/components/ScholarLink.svelte';

	let { data, children }: { data: LayoutData; children: Snippet } = $props();
	const { venue } = $derived(data);
</script>

{#if venue === null}
	<Page title="Unknown venue" breadcrumbs={[[`/venues`, 'Venue']]}>
		<p>Unable to find this venue.</p>
	</Page>
{:else if venue.inactive !== null && !venue.editors.includes(data.scholar?.id ?? '')}
	<Page title={venue.title} breadcrumbs={[[`/venues`, 'Venues']]}>
		{#snippet subtitle()}Venue{/snippet}
		{#snippet details()}<Link to={venue.url}>{venue.url}</Link> Editors: {#each venue.editors as editorID}
				<ScholarLink id={editorID} />
			{/each}{/snippet}
		<Note error><strong>{venue.inactive}</strong></Note>
	</Page>
{:else}
	{#if venue.inactive !== null}
		<Note error
			>This venue is currently inactive. Only you and other editors can see it, whereas everyone
			else sees this message: "{venue.inactive}". When you're ready, activate it in <Link
				to="/venue/{venue.id}/settings">venue settings</Link
			>.</Note
		>
	{/if}
	{@render children()}
{/if}
