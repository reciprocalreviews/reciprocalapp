<script lang="ts">
	import type { Snippet } from 'svelte';
	import type { LayoutData } from './$types';
	import Page from '$lib/components/Page.svelte';
	import Link from '$lib/components/Link.svelte';
	import ScholarLink from '$lib/components/ScholarLink.svelte';
	import Feedback from '$lib/components/Feedback.svelte';

	let { data, children }: { data: LayoutData; children: Snippet } = $props();
	const { venue } = $derived(data);
</script>

{#if venue === null}
	<Page title="Unknown venue" breadcrumbs={[[`/venues`, 'Venue']]}>
		<p>Unable to find this venue.</p>
	</Page>
{:else if venue.inactive !== null && !venue.admins.includes(data.scholar?.id ?? '')}
	<Page title={venue.title} breadcrumbs={[[`/venues`, 'Venues']]}>
		{#snippet subtitle()}Venue{/snippet}
		{#snippet details()}<Link to={venue.url}>{venue.url}</Link> Admins: {#each venue.admins as adminID}
				<ScholarLink id={adminID} />
			{/each}{/snippet}
		<Feedback error>
			<p>
				This venue is currently <strong>inactive</strong>, so only admins can see its details. Here
				is the message from the admins.
			</p>
			<p><em>{venue.inactive}</em></p>
		</Feedback>
	</Page>
{:else}
	{#if venue.inactive !== null}
		<Feedback error
			>This venue is currently <strong>inactive</strong>. Only you and other admins can see it,
			along with the message set in the <Link to="/venue/{venue.id}/settings">venue settings</Link>.
			Visit the settings to activate the venue.</Feedback
		>
	{/if}
	{@render children()}
{/if}
