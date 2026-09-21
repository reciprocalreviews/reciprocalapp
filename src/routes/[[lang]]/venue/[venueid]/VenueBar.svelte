<script lang="ts">
	import Link from '$lib/components/Link.svelte';
	import Overflow from '$lib/components/Overflow.svelte';
	import measure from '$lib/components/measure';
	import { VenueLabel } from '$lib/components/Labels';
	import {
		venueBarLinks,
		venueBarName,
		type VenueBarLink,
		type VenueBarVenue
	} from '$lib/data/venueBarLinks';
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

	/** The row whose width decides what fits. */
	let row = $state<HTMLElement | undefined>(undefined);
</script>

{#snippet barLink(link: VenueBarLink)}
	<Link size="small" to={link.href}>{link.label}</Link>
{/snippet}

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
<nav class="venue-bar" bind:this={row} use:measure={'--page-header-height'} data-testid="venue-bar">
	<!-- The short name, which is what this column of the bar is for: "ToK" fits where
	     "Transactions on Knowledge" does not, and the landing page still spells the full
	     title out. A venue that never chose one falls back to its title, so this truncates
	     rather than pushing the links off the end. Wrapped, so the freeze below can reach
	     it: the `<a>` inside is Link.svelte's and this component's scoped styles do not
	     land on it. -->
	<div class="home">
		<Link size="small" to={home} icon={VenueLabel} testid="venue-bar-home">
			<span class="name">{name}</span>
		</Link>
	</div>
	<Overflow
		strings={(l) => l.page.venue.bar.menu}
		testid="venue-menu"
		items={links}
		key={(link) => link.href}
		item={barLink}
		{row}
	/>
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
		/* With the padding below, `width: 100%` alone measured 1312px inside a 1280px
		   viewport and gave the whole document a horizontal scrollbar — which on a sticky
		   row is worse than it sounds, because scrolling sideways slides the chrome out of
		   view (#156). There is no global box-sizing reset in this project. */
		box-sizing: border-box;
		display: flex;
		flex-direction: row;
		/* Not `wrap`. Growing a second row is the thing this bar exists to stop. */
		flex-wrap: nowrap;
		/* Baselines, not boxes. `Link` appends a 🌐 to an external link as a `<sub>`, which
		   hangs below the text and makes that link's box taller than its neighbours' — so
		   centring the boxes pushed "Website" a couple of pixels above the words beside it.
		   Page.svelte's title band aligns on baselines for the same reason. */
		align-items: baseline;
		gap: var(--spacing);
		/* Declared, not discovered. What is in this row changes with the width — links
		   leave, the ☰ arrives, and they are not the same height — and this row's height is
		   `--page-header-height`, the sticky offset for the page below it. A row that grew
		   a few pixels when it collapsed would move the whole page vertically on a resize,
		   which is the one failure Page.svelte and breadcrumbs.ts exist to prevent. */
		min-height: var(--chrome-row-height);
		padding: var(--spacing-half) var(--spacing);
		/* The same turquoise every other page's title band is painted with. It was the
		   faded tint until the two were seen side by side on one contact sheet, where a
		   pale band inside a venue and a saturated one everywhere else read as two
		   different kinds of thing rather than as the same piece of chrome. No bottom
		   border: that was drawn to separate a pale band from the page, and a saturated
		   one separates itself. */
		background: var(--salient-color);
		/* Deliberately no `overflow: clip`: the overflow menu's panel has to escape this
		   box. `position: sticky` above already makes this the containing block it is
		   positioned against, so opening the menu cannot change this bar's own height —
		   which matters, because that height is what `--page-header-height` carries. */
	}

	/* The one item here with no length limit worth relying on, so it is the one allowed to
	   shrink — and therefore the one that has to be pinned while Overflow measures. Without
	   the second rule the bar absorbs every pixel of overflow by grinding this label down,
	   never reports being full, and no link ever collapses. */
	.home {
		flex: 0 1 auto;
		/* A floor rather than zero. Allowed to shrink all the way, this collapsed to no
		   width at all and its label wrapped into a second line, which grew the bar — and
		   the bar's height is a sticky offset for the page under it. It truncates now, and
		   the ellipsis on `.name` is what makes truncation legible. */
		min-width: 4rem;
		white-space: nowrap;
	}

	/* `:global` on the attribute half is load-bearing, not stylistic: `data-fitting` is
	   written by JavaScript during a measurement, so Svelte's CSS pruner cannot see it and
	   drops the whole rule as unused — silently, and with it the freeze. */
	:global(.venue-bar[data-fitting]) .home {
		flex-shrink: 0;
	}

	/* White on the turquoise, the way Banner.svelte does it and for the same reason: the
	   colours a link inherits are chosen against the page's own ground and do not survive
	   a saturated one. The third rule is the one that is easy to miss — Link.svelte paints
	   the route you are on with `--text-color`, which is black. */
	.venue-bar :global(a) {
		color: var(--background-color);
	}

	/* ...except inside the overflow panel, which is its own surface. Left white-on-white
	   the open menu was simply blank. Painting the panel to match the bar keeps one rule
	   for the links and makes the menu read as part of the bar it drops out of. */
	.venue-bar :global([data-overflow-panel]) {
		background: var(--salient-color);
		border-color: var(--background-color);
	}

	.venue-bar :global(a .underline) {
		text-decoration-color: var(--background-color);
	}

	.venue-bar :global(a[aria-current]) {
		color: var(--background-color);
	}

	/* Which leaves the app's own convention to say where you are: every other link keeps
	   its underline, and the current one drops it. No new tab vocabulary. */

	/* The overflow toggle is a faded-turquoise chip by default, which is invisible on
	   turquoise. It is a glyph rather than a word, so it centres in the row rather than
	   sitting on the baseline the words share. */
	.venue-bar :global(button) {
		background: transparent;
		color: var(--background-color);
		align-self: center;
	}

	/* The home link's own box, so that the name below can be a BLOCK and still sit on the
	   row's baseline. A clipped box has to stop being inline-level for that to be possible
	   at all, and a block only gets a baseline its parent can use if its parent is looking
	   for one — hence the flex context here rather than one level up on `.home`, which
	   lands the baseline just as well and grows the bar from 48px to 64px. This bar's
	   height IS `--page-header-height`, so that is disqualifying rather than untidy.

	   A flex container ignores `vertical-align` on its items, so the 📚 `Link` appends
	   stops hanging below the text and sits on the baseline with it, about two pixels up.
	   That is the intended reading: the glyph belongs to the venue's name. "Website"'s 🌐
	   is a different link and still hangs, where it marks a link that leaves the site. */
	.venue-bar .home :global(a) {
		display: flex;
		align-items: baseline;
	}

	/* The one item here with no length limit worth relying on: a venue that chose no short
	   name falls back to a title its editors wrote. It loses, rather than pushing the
	   links it sits beside off the end of a row that no longer wraps. */
	.name {
		/* A block, and not an inline-block, for a reason no amount of `vertical-align`
		   could fix. `text-overflow: ellipsis` needs `overflow: hidden`, and an INLINE-level
		   box whose overflow is not `visible` takes its baseline from its bottom margin edge
		   rather than from its text (CSS 2.1 §10.8.1) — so while this was an inline-block it
		   had no usable baseline, and sat 3.45px below every other word in the bar. Removing
		   the `vertical-align: bottom` it used to carry moved it 7.39px the other way. As a
		   flex item of the rule above it is block-level, where that clause does not apply.

		   `display: block` also stops `text-decoration` propagating in, exactly as
		   `inline-block` did, so `Link`'s underline still has to be inherited explicitly or
		   the venue's name reads as the current route on every page inside the venue. */
		text-decoration: inherit;
		display: block;
		max-width: 12rem;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
</style>
