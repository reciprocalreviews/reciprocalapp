<script lang="ts">
	import Link from '$lib/components/Link.svelte';
	import { getAuth } from '../Auth.svelte';
	import Page from '$lib/components/Page.svelte';
	import Feedback from '$lib/components/Feedback.svelte';

	let { data } = $props();

	let proposals = $derived(data.proposals);
	let venues = $derived(data.venues);

	const auth = getAuth();
</script>

<Page title="Venues" subtitle={undefined}>
	<p>
		These are journals and conferences using Reciprocal Reviews to track and incentivize peer
		review. Choose one to see it's policies or volunteer to review for it, or propose a new one.
	</p>

	{#if auth.isAuthenticated()}<Link to="/venues/proposal">Propose a new venue</Link>{/if}

	<h2>Proposed venues</h2>
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
				>No venues have been proposed yet. {#if !auth.isAuthenticated()}Log in to propose one.{/if}</Feedback
			>
		{/if}
	{:else}
		<Feedback error>We couldn't load the venue proposals.</Feedback>
	{/if}

	<h2>Active venues</h2>

	{#if venues}
		{#if venues.length > 0}
			<ul>
				{#each venues.toSorted((a, b) => a.title.localeCompare(b.title)) as venue}
					<li>
						<Link to="/venue/{venue.id}"
							>{#if venue.title.length === 0}<em>Unnamed</em>{:else}{venue.title}{/if}</Link
						>
					</li>
				{/each}
			</ul>
		{:else}
			<Feedback>There are no active venues.</Feedback>
		{/if}
	{:else}
		<Feedback error>We couldn't load the venues.</Feedback>
	{/if}
</Page>
