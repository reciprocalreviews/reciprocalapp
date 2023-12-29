<script lang="ts">
	import { dev } from '$app/environment';
	import Lead from '$lib/components/Lead.svelte';
	import Link from '$lib/components/Link.svelte';
</script>

<h1>Reciprocal Reviews</h1>
{#if dev}
	<Lead>Sustain academic peer review by organizing availability and incentivizing reviewing.</Lead>
	<p>
		Academia incentivizes writing over reading, but depends on everyone to read their fair share.
		This means that there are never enough reviewers, reviews are late and often of low quality, and
		everyone is unhappy.
	</p>

	<p>
		<strong>Reciprocal Reviews</strong> is a community-run platform that addresses this asymmetry with
		two features:
	</p>

	<ul>
		<li>
			<strong>Reviewers volunteer and post their capacity</strong>. This helps scholars track their
			volunteer efforts and helps editors find reviewers who are available.
		</li>
		<li>
			<strong>Editors set a cost for submission, priced in <em>review tokens</em></strong>.
			Co-authors split the cost by writing reviews and pay at the time of submission. Editors
			compensate reviewers and editors for reviews of sufficient quality.
		</li>
	</ul>

	<p>
		Editors can more easily find available reviewers, editors can hold reviewers accountable to
		qualitity and timeline, and to make it all work, we'll all submit fewer, more polished
		publications.
	</p>

	<p>
		If you're an journal editor or conference program chair and want to learn more, see the <Link
			to="/sources">journals and conferences</Link
		> using the platform, and reach out to their editors for their experiences. Or, log in and get started.
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

	<iframe
		src="https://reciprocalreviews.substack.com/embed"
		title="Newsletter subscription"
		width="480"
		height="150"
		style="border:none; background:white;"
		frameborder="0"
		scrolling="no"
	/>
{/if}
