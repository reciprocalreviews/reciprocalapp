<script lang="ts">
	import Link from '$lib/components/Link.svelte';
	import { getDB } from '$lib/data/Database';
	import { getAuth } from '../Auth.svelte';
	import Page from '$lib/components/Page.svelte';
	import type { ProposalRow } from '../../data/types';
	import Feedback from '$lib/components/Feedback.svelte';

	let { data }: { data: { proposals: ProposalRow[] | null } } = $props();

	let proposals = $derived(data.proposals);

	const db = getDB();
	const auth = getAuth();
</script>

<Page title="Venues">
	<h1>Venues</h1>

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
		<Feedback error>We couldn't load the proposed venues.</Feedback>
	{/if}

	<!-- {#await db.getSources()}
		<Loading />
	{:then sources}
		<ul>
			{#each sources.toSorted((a, b) => a.name.localeCompare(b.name)) as source}
				<li>
					<Link to="/source/{source.id}"
						>{#if source.name.length === 0}<em>Unnamed</em>{:else}{source.name}{/if}</Link
					>
				</li>
			{/each}
		</ul>
	{:catch}
		<Feedback>We couldn't load the sources.</Feedback>
	{/await} -->
</Page>
