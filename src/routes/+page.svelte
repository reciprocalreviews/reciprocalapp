<script lang="ts">
	import Tip from '$lib/components/Tip.svelte';
	import Link from '$lib/components/Link.svelte';
	import Page from '$lib/components/Page.svelte';
	import Tokens from '$lib/components/Tokens.svelte';
	import { PUBLIC_ENV } from '$env/static/public';
	import Feedback from '$lib/components/Feedback.svelte';
	import { TokenLabel } from '$lib/components/Labels';

	const inProd = PUBLIC_ENV === 'prod';
</script>

<svelte:head>
	<title>Reciprocal Reviews</title>
</svelte:head>

<Page icon={TokenLabel} title="Reciprocal Reviews" breadcrumbs={[]}>
	{#snippet subtitle()}Make peer review count.{/snippet}
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
		faster reviews, editors do less nagging, communities overall have a fairer distribution of peer
		review labor.
	</p>

	{#if !inProd}
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
		<Feedback>
			We're in development! A public beta is likely in 2026. Visit <Link
				to="https://github.com/reciprocalreviews">GitHub</Link
			>
			to see who's involved, see our <Link
				to="https://github.com/reciprocalreviews/reciprocalapp/issues?q=is:open%20milestone:%22Beta%22"
				>beta milestone</Link
			> for the work that remains. Subscribe to our low-volume
			<Link to="https://reciprocalreviews.substack.com/">newsletter</Link> to follow along. And if you
			feel like helping, email us! We're a small volunteer group of academics.
		</Feedback>
	{/if}
</Page>
