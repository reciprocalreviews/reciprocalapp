<script lang="ts">
	import { dev } from '$app/environment';
	import Lead from '$lib/components/Lead.svelte';
	import Link from '$lib/components/Link.svelte';
	import Tag from '$lib/components/Tag.svelte';
	import Page from '$lib/components/Page.svelte';
	import Tokens from '$lib/components/Tokens.svelte';
</script>

<svelte:head>
	<title>Reciprocal Reviews</title>
</svelte:head>

<Page title="Reciprocal Reviews" subtitle="Make peer review count.">
	{#if dev}
		<p>
			Academia incentivizes publishing over peer review. That means too many submissions and not
			enough reviews, or reviews that are late and low quality.
		</p>

		<p>
			<strong>Reciprocal Reviews</strong> breaks this cycle:
		</p>

		<ol>
			<li>
				<strong>Editors set a cost</strong> for submissions, priced in <em>review tokens</em>, e.g.
				<Tokens amount={10}></Tokens>.
			</li>
			<li>
				<strong>Authors earn tokens</strong> by volunteering for venues, sharing expertise and availability,
				and submitting on-time, quality reviews.
			</li>
			<li>
				<strong>Authors spend tokens</strong> to submit manuscripts for review, splitting the cost with
				co-authors. Or, they can gift tokens to individuals or community pools for strategic investments
				in equity and emerging topics.
			</li>
		</ol>

		<p>
			Authors get better, faster reviews and a fairer distribution of peer review labor; editors do
			less nagging.
		</p>

		<p>
			See the <Link to="/sources">journals and conferences</Link> using the platform and reach out to
			their editors for their experiences. Or, <Link to="login">log in</Link> to propose a journal or
			conference for adoption.
		</p>

		<p>
			<strong>Don't want to set a cost?</strong> Use Reciprocal Reviews to track volunteer reviewers
			in your community, tracking volunteers for streamlined editing.
		</p>
	{:else}
		<p>
			We're a volunteer community of academics striving for more equitable and sustainable academic
			peer review. This site will eventually be a platform for tracking reviewer availabilty and
			contributions in a way that ensures sufficient reviewing labor for submissions. Visit <Link
				to="https://github.com/reciprocalreviews">GitHub</Link
			>
			to learn more and contribute or subscribe to our twice monthly
			<Link to="https://reciprocalreviews.substack.com/">newsletter</Link>:
		</p>
	{/if}

	<h2>Updates</h2>

	<p>Follow along on our newsletter.</p>

	<iframe
		src="https://reciprocalreviews.substack.com/embed"
		title="Newsletter subscription"
		width="480"
		height="150"
		style="border:none; background:white;"
		frameborder="0"
		scrolling="no"
	></iframe>
</Page>
