<script lang="ts">
	import Link from '$lib/components/Link.svelte';
	import { getAuth } from '../Auth.svelte';
	import Page from '$lib/components/Page.svelte';
	import Feedback from '$lib/components/Feedback.svelte';
	import VenueLink from '$lib/components/VenueLink.svelte';
	import Subheader from '$lib/components/Subheader.svelte';
	import { VenueLabel } from '$lib/components/Labels';

	let { data } = $props();

	let proposals = $derived(data.proposals);
	let venues = $derived(data.venues);

	const auth = getAuth();
</script>

<Page title="Venues" breadcrumbs={[]}>
	<p>
		These are journals and conferences using Reciprocal Reviews to track and incentivize peer
		review. Choose one to see it's policies or volunteer to review for it, or propose a new one.
	</p>

	{#if auth.isAuthenticated()}<Link to="/venues/proposal">Propose a new venue</Link>{/if}

	<Subheader icon={VenueLabel}>Active venues</Subheader>

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
			<Feedback>There are no active venues.</Feedback>
		{/if}
	{:else}
		<Feedback error>We couldn't load the venues.</Feedback>
	{/if}

	<Subheader icon={VenueLabel}>Proposed venues</Subheader>
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
			<Feedback
				>No venues have been proposed yet. {#if !auth.isAuthenticated()}<Link to="/login"
						>Log in</Link
					> to propose one.{/if}</Feedback
			>
		{/if}
	{:else}
		<Feedback error>We couldn't load the venue proposals.</Feedback>
	{/if}
</Page>
