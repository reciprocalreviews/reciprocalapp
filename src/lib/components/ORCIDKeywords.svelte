<script lang="ts">
	import { getLocaleContext } from '$routes/Contexts';
	import ORCIDMark from './ORCIDMark.svelte';
	import Tag from './Tag.svelte';

	const locale = getLocaleContext();

	let {
		keywords,
		/** Let long keywords wrap. On by default in a table, where one unbreakable tag sets
		 * the minimum width of the whole column. */
		wrap = true,
		testid = undefined
	}: { keywords: string[]; wrap?: boolean; testid?: string } = $props();
</script>

<!--
	A scholar's self-declared ORCID keywords, marked as ORCID's.

	The mark is what carries the provenance, and it travels with the chips rather than sitting
	on a boundary above them. That is the whole design of this component: these used to be set
	apart by a dotted rule, which drew with nothing above it whenever a volunteer had written
	no expertise for the venue — a separator separating one thing from nothing. Hiding the rule
	in that case would have been worse, because it is exactly the case where an unmarked row of
	chips reads as the venue's own expertise. Marking the chips themselves cannot go wrong
	either way.

	These are deliberately NOT clickable. The expertise chips above them on the roster are
	filters over what volunteers wrote for this venue about reviewing; these describe a research
	career, and they never enter that filter's ranking (see volunteersView's `tags`).

	Renders nothing at all for an empty list, so no caller needs a guard.
-->
{#if keywords.length > 0}
	<span class="orcid-keywords" data-testid={testid}>
		<ORCIDMark decorative />
		<!-- Announced, not a title attribute: a `title` on a span is not reliably read out,
		     and without it a screen reader gets a bare list of words with nothing saying
		     whose they are. -->
		<span class="label">{locale().view.expertise.orcid}</span>
		{#each keywords as keyword (keyword)}<Tag {wrap}>{keyword}</Tag>{/each}
	</span>
{/if}

<style>
	.orcid-keywords {
		/* Block-level, so the two sources stack rather than running together on one line.
		   Each row carries its own mark, so a row that is absent takes no space and leaves
		   no gap — which is the property the old dotted rule could not have. */
		display: flex;
		width: fit-content;
		max-width: 100%;
		flex-wrap: wrap;
		/* Centred, not baseline-aligned: an SVG has no baseline, so `baseline` puts its
		   bottom edge on the text's and lifts the mark above the optical centre of the
		   chips beside it. */
		align-items: center;
		gap: var(--spacing-half);
		/* No border, margin or padding above: there is deliberately no separator here. */
	}

	/* Visually hidden, still announced. Scoped to this component rather than added as a
	   global utility, since nothing else in the app needs one yet. */
	.label {
		position: absolute;
		width: 1px;
		height: 1px;
		margin: -1px;
		padding: 0;
		overflow: hidden;
		clip-path: inset(50%);
		white-space: nowrap;
		border: 0;
	}
</style>
