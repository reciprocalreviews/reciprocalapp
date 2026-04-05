<script lang="ts">
	import Feedback from '$lib/components/Feedback.svelte';
	import { VenueLabel } from '$lib/components/Labels';
	import Link from '$lib/components/Link.svelte';
	import Page from '$lib/components/Page.svelte';
	import Subheader from '$lib/components/Subheader.svelte';
	import VenueLink from '$lib/components/VenueLink.svelte';
	import Text from '$lib/locales/Text.svelte';
	import { getAuth } from '$routes/Auth.svelte';

	let { data } = $props();

	let proposals = $derived(data.proposals);
	let venues = $derived(data.venues);

	const auth = getAuth();
</script>

<Page icon={VenueLabel} title={(l) => l.page.venues.title} breadcrumbs={[]}>
	<Text markdown path={(l) => l.page.venues.description} />

	{#if auth().isAuthenticated()}<Link to="/venues/proposal"
			><Text path={(l) => l.page.venues.link.propose} /></Link
		>{/if}

	<Subheader icon={VenueLabel} text={(l) => l.page.venues.header.active} />

	{#if venues}
		{#if venues.length > 0}
			<ul>
				{#each venues.toSorted((a, b) => a.title.localeCompare(b.title)) as venue, index}
					<li>
						<VenueLink id={venue.id} name={venue.title} testid={'venue-' + index}></VenueLink>
					</li>
				{/each}
			</ul>
		{:else}
			<Feedback text={(l) => l.page.venues.feedback.noVenues} />
		{/if}
	{:else}
		<Feedback error text={(l) => l.page.venues.feedback.venuesNotLoaded} />
	{/if}

	<Subheader icon={VenueLabel} text={(l) => l.page.venues.header.proposed} />

	{#if proposals !== null}
		{#if proposals.length > 0}
			<ul>
				{#each proposals.toSorted((a, b) => a.title.localeCompare(b.title)) as proposal}
					<li>
						<Link to="/venues/proposal/{proposal.id}"
							>{#if proposal.title.length === 0}<em>Unnamed</em>{:else}{proposal.title}{/if}</Link
						>
					</li>
				{/each}
			</ul>
		{:else}
			<Feedback text={(l) => l.page.venues.feedback.noProposals} />
		{/if}
	{:else}
		<Feedback error text={(l) => l.page.venues.feedback.proposalsNotLoaded} />
	{/if}
</Page>
