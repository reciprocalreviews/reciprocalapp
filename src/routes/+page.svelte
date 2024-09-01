<script lang="ts">
	import { dev } from '$app/environment';
	import Lead from '$lib/components/Lead.svelte';
	import Link from '$lib/components/Link.svelte';
	import Tag from '$lib/components/Tag.svelte';
</script>

<svelte:head>
	<title>Reciprocal Reviews</title>
</svelte:head>

<h1>Reciprocal Reviews</h1>
{#if dev}
	<Lead>Incentivize on-time, quality peer reviews.</Lead>
	<p>
		Academia incentivizes publishing over reviewing. That means too many submissions and not enough
		reviews, or reviews that are late and low quality.
	</p>

	<p>
		<strong>Reciprocal Reviews</strong> breaks this cycle:
	</p>

	<ol>
		<li>
			<strong>Editors set an cost for submission</strong>, priced in <Tag>review tokens</Tag>.
		</li>
		<li>
			<strong>Authors earn tokens</strong> by volunteering for venues, sharing expertise and availabilty,
			and submitting on-time, quality reviews.
		</li>
		<li>
			<strong>Authors spend tokens</strong> to submit manuscripts for review, splitting the cost with
			co-authors. Or, they can gift tokens to colleagues in or donate their tokens to the community pool
			for strategic investiments in equity and emerging areas.
		</li>
	</ol>

	<p>
		See the <Link to="/sources">journals and conferences</Link> using the platform and reach out to their
		editors for their experiences. Or, <Link to="login">Log in</Link> to propose a journal or conference
		for adoption.
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

<hr />

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
