<script lang="ts">
	import type { PublicORCIDProfile } from '$data/types';
	import {
		affiliationLine,
		educationLine,
		hasAnything,
		keywords,
		links,
		shouldReportProblem,
		works,
		worksStat
	} from '$lib/data/orcidProfileView';
	import { getLocaleContext } from '$routes/Contexts';
	import Feedback from './Feedback.svelte';
	import { ScholarLabel } from './Labels';
	import Link from './Link.svelte';
	import Subheader from './Subheader.svelte';
	import ORCIDKeywords from './ORCIDKeywords.svelte';

	let {
		profile,
		/** Whether the viewer is the scholar themselves. Governs one thing only: whether a
		 * failed or missing record is reported. */
		own = false
	}: { profile: PublicORCIDProfile | null; own?: boolean } = $props();

	const locale = getLocaleContext();

	let affiliation = $derived(affiliationLine(profile));
	let education = $derived(educationLine(profile));
	let topics = $derived(keywords(profile));
	let recent = $derived(works(profile));
	let stat = $derived(worksStat(profile));
	let elsewhere = $derived(links(profile));
	let show = $derived(hasAnything(profile));
</script>

<!--
	The mirrored slice of a scholar's public ORCID record.

	Absence renders as ABSENCE. No header, no placeholder, no skeleton, no "unknown" — a
	heading with nothing under it tells a visitor this person has no career, which is false:
	it means they made nothing public on ORCID, or RR has not read them yet. The ORCID link
	in the page's details is already there and is the honest fallback.

	The one asymmetry is failure. A visitor is told nothing when RR could not read the record
	— on a public profile that reads as an accusation, and they can do nothing about it — and
	the scholar themselves is told, because they are the only person who can act on it.
-->
{#if show}
	<Subheader icon={ScholarLabel} id="orcid" text={(l) => l.view.orcid.header}></Subheader>

	<dl>
		{#if affiliation}
			<dt>{locale().view.orcid.affiliation}</dt>
			<dd data-testid="orcid-affiliation">{affiliation}</dd>
		{/if}
		{#if education}
			<dt>{locale().view.orcid.education}</dt>
			<dd data-testid="orcid-education">{education}</dd>
		{/if}
		{#if topics.length > 0}
			<dt>{locale().view.orcid.keywords}</dt>
			<dd data-testid="orcid-keywords">
				<!-- The same component the roster and the assignment table use, so the treatment
				     is identical everywhere ORCID keywords appear. Its mark is redundant under
				     this section's own heading, but consistency is worth more than the pixel. -->
				<ORCIDKeywords keywords={topics} wrap={false} />
			</dd>
		{/if}
		{#if stat}
			<dt>{locale().view.orcid.works}</dt>
			<dd data-testid="orcid-works">
				<span class="stat">{stat}</span>
				{#if recent.length > 0}
					<ul>
						<!-- Unkeyed on purpose, and it matters. A work has no id, so the only key
						     available is its own content — and an ORCID record may legally hold the same
						     title twice. A duplicate key THROWS in Svelte, in production as well as in
						     development, and the throw escapes hydration, which leaves the page drawn and
						     styled with every button on it wired to nothing. Nothing reorders here, so a
						     key would buy nothing and risk that. -->
						{#each recent as work}
							<li>
								{#if work.url}<Link to={work.url}>{work.title}</Link>{:else}{work.title}{/if}
								<span class="meta">
									{#if work.journal}{work.journal}{/if}{#if work.journal && work.year},
									{/if}{#if work.year}{work.year}{/if}
								</span>
							</li>
						{/each}
					</ul>
				{/if}
			</dd>
		{/if}
		{#if elsewhere.length > 0}
			<dt>{locale().view.orcid.links}</dt>
			<dd data-testid="orcid-links">
				<span class="tags">
					<!-- Unkeyed, for the reason above. This is the list that actually broke: a real
					     record carried its ResearcherID twice, `label + value` collided, and that
					     scholar's whole profile page went inert. -->
					{#each elsewhere as link}
						{#if link.url}<Link to={link.url}>{link.label}</Link>{:else}{link.label}: {link.value}{/if}
					{/each}
				</span>
			</dd>
		{/if}
	</dl>

	<!--
		Provenance, and it earns its place: it is the sentence that keeps everything above
		from reading as Reciprocal Reviews' claim about this person rather than as a copy of
		what they published themselves. Shown whenever the section is.
	-->
	{#if profile?.fetched_at}
		<p class="provenance" data-testid="orcid-provenance">
			{(own ? locale().view.orcid.provenanceOwn : locale().view.orcid.provenance).replace(
				'{date}',
				new Date(Date.parse(profile.fetched_at)).toLocaleDateString()
			)}
		</p>
	{/if}
{/if}

{#if own && shouldReportProblem(profile)}
	<Feedback inline={false} testid="orcid-problem" text={(l) => l.view.orcid.problem} />
{/if}

<style>
	dl {
		display: grid;
		grid-template-columns: auto 1fr;
		gap: var(--spacing-half) var(--spacing);
		margin: 0;
		align-items: baseline;
	}

	dt {
		font-size: var(--small-font-size);
		color: var(--inactive-color);
		white-space: nowrap;
	}

	dd {
		margin: 0;
		min-width: 0;
	}

	/* One column on a narrow screen: the two-column grid puts a long affiliation into a
	   sliver beside its label. */
	@media (max-width: 30rem) {
		dl {
			grid-template-columns: 1fr;
			gap: 0 0;
		}

		dd {
			margin-block-end: var(--spacing-half);
		}
	}

	.tags {
		display: inline-flex;
		flex-wrap: wrap;
		gap: var(--spacing-half);
		align-items: baseline;
	}

	ul {
		margin: var(--spacing-half) 0 0 0;
		padding-inline-start: var(--spacing);
	}

	li {
		margin-block-end: var(--spacing-half);
	}

	.stat {
		font-size: var(--small-font-size);
		color: var(--inactive-color);
	}

	.meta {
		font-size: var(--small-font-size);
		color: var(--inactive-color);
	}

	.provenance {
		font-size: var(--small-font-size);
		color: var(--inactive-color);
		margin-block-start: var(--spacing-half);
	}
</style>
