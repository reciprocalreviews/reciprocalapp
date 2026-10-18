<script lang="ts">
	import Alert from '#lib/components/Alert.svelte';
	import ContextBar from '#lib/components/ContextBar.svelte';
	import { venuesBar } from '#lib/data/contextBar.js';
	import { closedVenueBar } from '#lib/data/venueBarLinks.js';
	import { getLocaleContext } from '$routes/Contexts';
	import Link from '#lib/components/Link.svelte';
	import Page from '#lib/components/Page.svelte';
	import Paragraph from '#lib/components/Paragraph.svelte';
	import ScholarLink from '#lib/components/ScholarLink.svelte';
	import { reloadOnChanges } from '#lib/data/SupabaseRealtime.js';
	import VenueBar from './VenueBar.svelte';
	import { NO_VENUE_ID } from '#lib/data/venuePath.js';
	import Text from '#lib/locales/Text.svelte';
	import type { Snippet } from 'svelte';
	import type { LayoutData } from './$types';

	let { data, children }: { data: LayoutData; children: Snippet } = $props();
	const { venue } = $derived(data);

	const locale = getLocaleContext();

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
		// The two transactions filters below already cover every change to the
		// venue's reserve: only a transaction can move a token. Watching `tokens`
		// as well meant a payout of N tokens woke every client on any page under
		// this venue N times over, each waking re-running the whole dashboard load.
		{ table: 'transactions', filter: `from_venue=eq.${venueid}` },
		{ table: 'transactions', filter: `to_venue=eq.${venueid}` },
		{ table: 'submissions', filter: `venue=eq.${venueid}` },
		{ table: 'assignments', filter: `venue=eq.${venueid}` }
	]);
</script>

<!-- Every branch draws exactly one bar: the root layout leaves venue routes to this one. -->
{#if venue === null}
	<!-- No venue to name, so the bar of the venue list, which is where to look instead. -->
	<ContextBar
		bar={venuesBar(locale(), data.scholar !== null)}
		menu={(l) => l.header.context.menu}
	/>
	<Page title={(l) => l.page.venue.unknownTitle}>
		<Paragraph text={(l) => l.page.venue.paragraph.notFound} />
	</Page>
{:else if venue.inactive !== null && !venue.admins.includes(data.scholar?.id ?? '')}
	<!-- A dead end, so the bar names the venue and offers only its website. The details row
	     stays — on a page that only says "you cannot come in", the website and the admins to
	     ask are the whole of what it can usefully offer. -->
	<ContextBar
		bar={closedVenueBar(venue, locale())}
		menu={(l) => l.page.venue.bar.menu}
		testid="venue-bar"
		menuTestid="venue-menu"
	/>
	<Page title={venue.title}>
		{#snippet subtitle()}<Text path={(l) => l.page.venue.title} />{/snippet}
		{#snippet details()}
			<Link to={venue.url}>{venue.url}</Link>
			<Text path={(l) => l.shorthand.admin} />
			{#each venue.admins as adminID}
				<ScholarLink id={adminID} />
			{/each}
		{/snippet}
		<!-- Attention rather than error: the venue is not broken, it is closed, and the
		     message is the admins' word on when it will open. -->
		<Alert
			tone="attention"
			text={(l) => l.page.venue.feedback.inactive}
			inputs={{ message: venue.inactive }}
			testid="venue-inactive-notice"
		/>
	</Page>
{:else}
	<!-- An admin of an inactive venue is told so by a chip in the bar on every page, and by
	     an alert only where it can be acted on — the landing page and settings. An alert
	     here, above every page's title, said the same thing on every click inside the venue
	     and sat outside the page's own anatomy. -->
	<VenueBar {venue} scholarID={data.scholar?.id ?? null} inactive={venue.inactive !== null} />
	{@render children()}
{/if}
