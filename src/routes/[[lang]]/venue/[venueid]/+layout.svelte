<script lang="ts">
	import Feedback from '$lib/components/Feedback.svelte';
	import { ErrorLabel, VenueLabel } from '$lib/components/Labels';
	import Link from '$lib/components/Link.svelte';
	import Page from '$lib/components/Page.svelte';
	import Paragraph from '$lib/components/Paragraph.svelte';
	import ScholarLink from '$lib/components/ScholarLink.svelte';
	import { reloadOnChanges } from '$lib/data/SupabaseRealtime';
	import { NO_VENUE_ID, venuePath } from '$lib/data/venuePath';
	import Text from '$lib/locales/Text.svelte';
	import type { Snippet } from 'svelte';
	import type { LayoutData } from './$types';

	let { data, children }: { data: LayoutData; children: Snippet } = $props();
	const { venue } = $derived(data);

	// Reload when the venue or its related data changes. Keyed on the resolved venue's id,
	// not the URL segment: these filters are matched against uuid columns in Postgres, so a
	// venue reached by its web address would subscribe to nothing and the page would quietly
	// stop updating itself.
	// Captured once, deliberately: `reloadOnChanges` subscribes in `onMount` and holds the
	// filters it was given, so a reactive read here would promise an updating value to
	// something that only ever reads it at mount.
	// svelte-ignore state_referenced_locally
	const venueid = data.venue?.id ?? NO_VENUE_ID;
	reloadOnChanges('venue_changes', [
		{ table: 'venues', filter: `id=eq.${venueid}` },
		{ table: 'roles', filter: `venueid=eq.${venueid}` },
		{ table: 'transactions', filter: `from_venue=eq.${venueid}` },
		{ table: 'transactions', filter: `to_venue=eq.${venueid}` },
		{ table: 'tokens', filter: `venue=eq.${venueid}` },
		{ table: 'submissions', filter: `venue=eq.${venueid}` },
		{ table: 'assignments', filter: `venue=eq.${venueid}` }
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
			testid="venue-inactive-notice"
		/>
	</Page>
{:else}
	{#if venue.inactive !== null}
		<Feedback
			error
			inline={false}
			text={(l) => l.page.venue.feedback.inactivePrompt.replace('{venue}', venuePath(venue))}
		/>
	{/if}
	{@render children()}
{/if}
