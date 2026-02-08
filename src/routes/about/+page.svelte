<script>
	import Feedback from '$lib/components/Feedback.svelte';
	import { IdeaLabel, ScholarLabel } from '$lib/components/Labels.js';
	import Link from '$lib/components/Link.svelte';
	import Page from '$lib/components/Page.svelte';
	import Subheader from '$lib/components/Subheader.svelte';

	let { data } = $props();
	let { stewards } = $derived(data);
</script>

<Page title="About" breadcrumbs={[]}>
	<p>
		We are a volunteer community of academics interested in keeping peer review sustainable, for
		ourselves and our communities. You can learn more about who's contributing and how to contribute
		yourself on <Link to="https://github.com/reciprocalreviews">GitHub</Link>.
	</p>

	<Subheader icon={ScholarLabel}>Stewards</Subheader>

	<p>
		Stewards oversee the platform and its use, guiding design, implementation, and usage with the
		goal of ensuring the platform is improving the sustainability of academic peer review:
	</p>

	<p>Current stewards are:</p>

	{#if stewards}
		<ul>
			{#each stewards as steward, index}
				<li>
					<Link to="/scholar/{steward.id}" testid={'steward-' + index}
						>{steward.name ?? 'anonymous'}</Link
					>
				</li>
			{/each}
		</ul>
	{:else}
		<Feedback>Unable to load active stewards.</Feedback>
	{/if}

	<p>Would you like to become a steward? Reach out to any of the stewards above and let's chat.</p>

	<Subheader icon={IdeaLabel}>Theory of change</Subheader>

	<p>The theory of change behind this platform is rests upon the following argument:</p>

	<ol>
		<li>
			Academia incentivizes, legitimizes, and values publishing over reviewing, in its culture and
			its many institutions' promotion criteria.
		</li>
		<li>
			Because of these incentives, many scholars do not review at a level that compensates for the
			reviewing labor they create when submitting, creating an imbalance between the number of
			submissions to review and the number of reviewers available.
		</li>
		<li>
			This imbalance also contributes in a reduction in quality of reviews, as both publishing
			incentives and anonymity encourage quick reviews, with the only incentive for quality being
			reputational loss.
		</li>
		<li>
			This imbalance has historically been addressed through inequitable and arbitrary means that do
			not address the underlying incentive mismatch:
			<ul>
				<li>
					Some scholars review at a much higher rate than others, due to their conscientiousness, or
					their fear of declining a request from a senior colleague, while others contribute no
					labor.
				</li>
				<li>
					Some venues place submission caps, limiting discovery in a coarse and ad hoc manner tied
					to identity that does not account for differences in productivity or resources.
				</li>
				<li>
					Some research communities call for changes to promotion criteria (e.g., tenure packets
					that only permit a fixed number of publications), but these are often adopted
					inconsistently across institutions and do not address cultural incentives.
				</li>
				<li>
					Communities try to create reviewer trainings to address quality, but many reviewers to not
					engage them.
				</li>
			</ul>
		</li>
		<li>
			The most direct way to address the root cause of the imbalance and review quality is to link
			rights to publish to high-quality reviewing labor in proportion to a scholar's submissions.
		</li>
		<li>
			Doing this in a direct way, such as requiring authors to review post submission in order for
			their submission to be published, often does not align with expertise needs or availability,
			creating a rigid structure for addressing imbalances (much like the rigidity of a <Link
				to="https://en.wikipedia.org/wiki/Barter">bartering system</Link
			>).
		</li>
		<li>
			<em>Reciprocal Reviews</em> instead proposes to use the well-understood alternative of a <Link
				to="https://en.wikipedia.org/wiki/Currency">currency system</Link
			>, requiring authors to first earn tokens by reviewing, and then spend those tokens on a right
			to publish.
		</li>
		<li>
			Creating this alignment not only ensures sufficient labor for the volume of submissions, but
			requires authors to account for that labor in their own workload by adding a cost to
			submitting, likely reducing the volume of submissions. It also gives power to editors to set a
			standard for review quality, only awarding tokens for reviews that meet that standard.
		</li>
		<li>
			Having a more liquid currency to reflect past reviewing effort also allows that currency to be
			spent in other creative ways, such as gifting labor to colleagues, investing in emerging
			research areas to defray the labor costs of review, and addressing inequities in academia
			stemming from resource imbalances, bias, and other factors by reducing or even eliminating
			some individuals and groups reviewing obligations, based on whatever norms a community wants
			to set.
		</li>
	</ol>

	<p>We built this platform to test the claims above, and hope you'll join us in this effort!</p>
</Page>
