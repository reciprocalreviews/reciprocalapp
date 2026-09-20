<script lang="ts">
	import Link from '$lib/components/Link.svelte';
	import Overflow from '$lib/components/Overflow.svelte';
	import measure from '$lib/components/measure';
	import { VenueLabel } from '$lib/components/Labels';
	import { venueBarLinks, venueBarName, type VenueBarVenue } from '$lib/data/venueBarLinks';
	import { venuePath } from '$lib/data/venuePath';
	import { getLocaleContext } from '$routes/Contexts';

	/**
	 * The venue's own band of chrome, on every route inside it.
	 *
	 * It replaces the per-page title band, which spent a full band of the viewport saying
	 * the venue's name and then, underneath, the name of the section just clicked — the
	 * locale file makes the case better than prose can, since `page.volunteers.subtitle`
	 * was the string "Volunteers", byte for byte identical to `page.volunteers.title`
	 * (#176). In the same space this names the venue AND reaches the five places inside it
	 * people actually go, which used to be two or three clicks deep.
	 *
	 * Which links appear is decided by `venueBarLinks`, not here: the gates it applies
	 * (payment-free, admin-only, no website) are rules, and rules in this codebase live in
	 * modules where a unit test can reach them.
	 */
	let {
		venue,
		scholarID
	}: {
		venue: VenueBarVenue;
		/** The signed-in scholar, or null when anonymous. Decides only whether Settings shows. */
		scholarID: string | null;
	} = $props();

	const locale = getLocaleContext();

	const links = $derived(venueBarLinks(venue, scholarID, locale()));
	const name = $derived(venueBarName(venue));
	const home = $derived(`/venue/${venuePath(venue)}`);
</script>

<!--
	The lower of two sticky bands, in the DOM position Page.svelte's title block used to
	occupy, and pinned by the same recipe.

	`use:measure={'--page-header-height'}` is that property's whole point: it means "the
	height of the band below the nav", and on these routes this is that band. So
	`scroll-padding-block-start` in app.html keeps working untouched. It does rely on
	Page.svelte not also writing it here, which is why every `<Page>` under `/venue/`
	passes `band={false}` — two ResizeObservers on one custom property fight, and what
	that produces is a jitter no test would catch.
-->
<nav class="venue-bar" use:measure={'--page-header-height'} data-testid="venue-bar">
	<!-- The short name, which is what this column of the bar is for: "ToK" fits where
	     "Transactions on Knowledge" does not, and the landing page still spells the full
	     title out. A venue that never chose one falls back to its title, so this truncates
	     rather than pushing the links off the end. -->
	<Link size="small" to={home} icon={VenueLabel} testid="venue-bar-home">
		<span class="name">{name}</span>
	</Link>
	{#each links.filter((link) => !link.overflow) as link}
		<div class="link">
			<Link size="small" to={link.href}>{link.label}</Link>
		</div>
	{/each}
	<Overflow strings={(l) => l.page.venue.bar.menu} testid="venue-menu">
		{#each links.filter((link) => link.overflow) as link}
			<div class="link">
				<Link size="small" to={link.href}>{link.label}</Link>
			</div>
		{/each}
	</Overflow>
</nav>

<style>
	.venue-bar {
		/* Pinned below the nav. The fallback is 0 for the same reason Page.svelte's band
		   uses 0 and app.html's scroll padding does not: a sticky box whose natural
		   position is ABOVE its threshold gets pushed down to meet it, so a fallback
		   larger than the real nav height opens a visible gap on every first paint that
		   then closes on hydration. Zero can never overshoot. */
		position: sticky;
		top: var(--nav-height, 0px);
		/* Below the nav's 2, so the nav wins if the measurement is ever momentarily stale. */
		z-index: 1;

		width: 100%;
		display: flex;
		flex-direction: row;
		/* Not `wrap`. Growing a second row is the thing this bar exists to stop. */
		flex-wrap: nowrap;
		align-items: center;
		gap: var(--spacing);
		padding: var(--spacing-half) var(--spacing);
		background: var(--salient-color-faded);
		border-block-end: var(--border-color) solid var(--border-width);
		/* Deliberately no `overflow: clip`: the overflow menu's panel has to escape this
		   box. `position: sticky` above already makes this the containing block it is
		   positioned against, so opening the menu cannot change this bar's own height —
		   which matters, because that height is what `--page-header-height` carries. */
	}

	.link {
		display: inline-block;
		flex: none;
	}

	/* The one item here with no length limit worth relying on: a venue that chose no short
	   name falls back to a title its editors wrote. It loses, rather than pushing the
	   links it sits beside off the end of a row that no longer wraps. */
	.name {
		display: inline-block;
		max-width: 12rem;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		vertical-align: bottom;
	}
</style>
