<script lang="ts">
	import Tip from '$lib/components/Tip.svelte';
	import Link from '$lib/components/Link.svelte';
	import Page from '$lib/components/Page.svelte';
	import Tokens from '$lib/components/Tokens.svelte';
	import { PUBLIC_ENV } from '$env/static/public';

	const inProd = PUBLIC_ENV === 'prod';
</script>

<svelte:head>
	<title>Reciprocal Reviews</title>
</svelte:head>

<Page title="Reciprocal Reviews" breadcrumbs={[]}>
	{#snippet subtitle()}Make peer review count.{/snippet}
	{#if !inProd}
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
				and submitting on-time, quality reviews, on whatever reviewing platform a venue uses.
			</li>
			<li>
				<strong>Authors spend tokens</strong> to submit manuscripts for review, splitting the cost with
				co-authors. Or, they can gift tokens to individuals or shared pools to strategically support newcomers,
				colleagues in crisis, or emerging topics.
			</li>
		</ol>

		<p>
			Because authors need to submit high-quality, on-time reviews to submit, authors get better,
			faster reviews, editors do less nagging, communities overall have a fairer distribution of
			peer review labor.
		</p>

		<Tip>
			<strong>Interested in adopting?</strong> See the <Link to="/venues"
				>journals and conferences</Link
			> using the platform and reach out to their editors for their experiences. Or, <Link
				to="login">log in</Link
			> to propose a journal or conference adopt <em>Reciprocal Reviews</em>.
		</Tip>

		<Tip>
			<strong>Don't want to set a cost?</strong> Use Reciprocal Reviews to track volunteer reviewers and
			expertise in your community, streamlining reviewing and program committee invitations.
		</Tip>

		<Tip
			><strong>We are a volunteer community</strong> of academics, not a for-profit organization.
			Our only goal is to improve the sustainability, quality, and integrity of peer review. See our <Link
				to="/about">about</Link
			> page if you're interested in helping.</Tip
		>
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
