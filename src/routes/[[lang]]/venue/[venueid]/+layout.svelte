<script lang="ts">
	import { page } from '$app/state';
	import Feedback from '$lib/components/Feedback.svelte';
	import { ErrorLabel, VenueLabel } from '$lib/components/Labels';
	import Link from '$lib/components/Link.svelte';
	import Page from '$lib/components/Page.svelte';
	import Paragraph from '$lib/components/Paragraph.svelte';
	import ScholarLink from '$lib/components/ScholarLink.svelte';
	import { reloadOnChanges } from '$lib/data/SupabaseRealtime';
	import Text from '$lib/locales/Text.svelte';
	import type { Snippet } from 'svelte';
	import type { LayoutData } from './$types';

	let { data, children }: { data: LayoutData; children: Snippet } = $props();
	const { venue } = $derived(data);

	// Reload when the venue or its related data changes.
	reloadOnChanges('venue_changes', [
		{ table: 'venues', filter: `id=eq.${page.params.venueid}` },
		{ table: 'roles', filter: `venueid=eq.${page.params.venueid}` },
		{ table: 'transactions', filter: `from_venue=eq.${page.params.venueid}` },
		{ table: 'transactions', filter: `to_venue=eq.${page.params.venueid}` },
		{ table: 'tokens', filter: `venue=eq.${page.params.venueid}` },
		{ table: 'submissions', filter: `venue=eq.${page.params.venueid}` },
		{ table: 'assignments', filter: `venue=eq.${page.params.venueid}` }
	]);
</script>

{#if venue === null}
	<Page icon={ErrorLabel} title={(l) => l.page.venue.unknownTitle} breadcrumbs={[]}>
		<Paragraph text={(l) => l.page.venue.paragraph.notFound} />
	</Page>
{:else if venue.inactive !== null && !venue.admins.includes(data.scholar?.id ?? '')}
	<Page icon={VenueLabel} title={venue.title} breadcrumbs={[]}>
		{#snippet subtitle()}<Text path={(l) => l.page.venue.subtitle} />{/snippet}
		{#snippet details()}
			<Link to={venue.url}>{venue.url}</Link>
			<Text path={(l) => l.shorthand.admin} />
			{#each venue.admins as adminID}
				<ScholarLink id={adminID} />
			{/each}
		{/snippet}
		<Feedback
			error
			inline={false}
			text={(l) => l.page.venue.feedback.inactive.replace('{message}', venue.inactive!)}
		/>
	</Page>
{:else}
	{#if venue.inactive !== null}
		<Feedback
			error
			inline={false}
			text={(l) => l.page.venue.feedback.inactive.replace('{venue}', venue.id)}
		/>
	{/if}
	{@render children()}
{/if}
