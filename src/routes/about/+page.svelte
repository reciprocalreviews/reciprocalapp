<script>
	import Feedback from '$lib/components/Feedback.svelte';
	import Link from '$lib/components/Link.svelte';
	import Page from '$lib/components/Page.svelte';

	let { data } = $props();
	let { stewards } = $derived(data);
</script>

<Page title="About" breadcrumbs={[]}>
	<p>
		We are a volunteer community of academics interested in keeping peer review sustainable, for
		ourselves and our communities. You can learn more about who's contributing and how to contribute
		yourself on <Link to="https://github.com/reciprocalreviews">GitHub</Link>.
	</p>

	<h2>Stewards</h2>

	<p>
		Stewards oversee the platform and its use, guiding design, implementation, and usage with the
		goal of ensuring the platform is improving the sustainability of academic peer review:
	</p>

	<p>Current stewards are:</p>

	{#if stewards}
		<ul>
			{#each stewards as steward}
				<li>
					<Link to="/scholar/{steward.id}">{steward.name ?? 'anonymous'}</Link>
				</li>
			{/each}
		</ul>
	{:else}
		<Feedback>Unable to load active stewards.</Feedback>
	{/if}

	<p>Would you like to become a steward? Reach out to us and let's chat.</p>
</Page>
