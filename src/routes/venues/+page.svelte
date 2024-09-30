<script lang="ts">
	import Link from '$lib/components/Link.svelte';
	import { getDB } from '$lib/data/Database';
	import { getAuth } from '../Auth.svelte';
	import Page from '$lib/components/Page.svelte';

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
