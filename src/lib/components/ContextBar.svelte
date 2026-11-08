<script lang="ts">
	import type LocaleText from '#lib/locales/Locale.js';
	import type { ButtonText } from '#lib/locales/Locale.js';
	import type { Bar, BarLink } from '#lib/data/contextBar.js';
	import Link from './Link.svelte';
	import Overflow from './Overflow.svelte';
	import measure from './measure';

	/**
	 * The teal band under the nav that names the area you are in and reaches the rest of it.
	 * Every route has exactly one: the venue bar inside a venue, and a bar from
	 * `contextBar.ts` everywhere else. What goes in it is decided there, not here.
	 */
	let {
		bar,
		menu,
		chip,
		testid = 'context-bar',
		menuTestid = `${testid}-menu`
	}: {
		bar: Bar;
		/** Names the control holding the links that do not fit on a narrow screen. */
		menu: (l: LocaleText) => ButtonText;
		/** A state of the area worth showing on every page in it, such as a venue being
		 * inactive. Links to where it can be changed. */
		chip?: { label: string; tip: string; href: string; testid?: string };
		/** Also prefixes the home link's (`-home`). */
		testid?: string;
		menuTestid?: string;
	} = $props();

	/** The row whose width decides what fits. */
	let row = $state<HTMLElement | undefined>(undefined);
</script>

{#snippet barLink(link: BarLink)}
	<Link size="small" to={link.href}>{link.label}</Link>
{/snippet}

<!--
	The lower of the two sticky bands, on every route: page titles render in the text column.

	`use:measure={'--page-header-height'}` is that property's whole point: it means "the
	height of the band below the nav", and this is the one element that writes it, so
	`scroll-padding-block-start` in app.html reserves it here and nothing elsewhere.
-->
<nav class="bar" use:measure={'--page-header-height'} data-testid={testid}>
	<!-- Two boxes, because the band has two jobs that one box cannot do at once. The nav
	     is the band: it declares the height and centres what is in it. This row is the
	     line of words: it sits its items on one baseline, and it is exactly one line tall
	     so that centring it centres the WORDS rather than a box the 🌐 has deepened. One
	     box doing both put the whole row 9.6px high in the band, since a baseline-aligned
	     container has no way to centre its group and gave every spare pixel to the bottom.

	     It is also what `Overflow` measures — the space the items actually have, which is
	     the nav's width less its padding, so the arithmetic is the same and it no longer
	     has to subtract padding that belongs to somebody else. -->
	<div class="row" bind:this={row}>
		<!-- The area's name. It truncates rather than pushing the links off the end. Wrapped,
		     so the freeze below can reach it: the `<a>` inside is Link.svelte's and this
		     component's scoped styles do not land on it. -->
		<div class="area">
			<Link size="small" to={bar.href} icon={bar.icon || null} testid="{testid}-home">
				<span class="name">{bar.name}</span>
			</Link>
		</div>
		{#if chip}
			<!-- A fact about the area rather than a place in it, so it sits with the name
			     and never collapses into the menu. It counts toward what Overflow measures,
			     being an in-flow child of the row. -->
			<a class="chip" href={chip.href} title={chip.tip} data-testid={chip.testid}>{chip.label}</a>
		{/if}
		<Overflow
			strings={menu}
			testid={menuTestid}
			items={bar.links}
			key={(link) => link.href}
			item={barLink}
			{row}
		/>
	</div>
</nav>

<style>
	.bar {
		/* Pinned below the nav. The fallback is 0 because a sticky box whose natural
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
		/* The band centres its one child. Baselines are the row's job, one level in: a
		   container aligned on baselines places that group at the top of the line and gives
		   every spare pixel to the bottom, so asking one box to do both left the whole row
		   sitting 9.6px high in a band half as tall again as the words in it. */
		align-items: center;
		/* Declared, not discovered. What is in this row changes with the width — links
		   leave, the ☰ arrives, and they are not the same height — and this row's height is
		   `--page-header-height`, the sticky offset for the page below it. A row that grew
		   a few pixels when it collapsed would move the whole page vertically on a resize. */
		min-height: var(--chrome-row-height);
		padding: var(--spacing-half) var(--spacing);
		/* Saturated turquoise, the brand colour, so it reads as chrome rather than as part
		   of the page. It was the faded tint, which next to the saturated title bands pages
		   used to have read as a different kind of thing. No bottom border: that was drawn
		   to separate a pale band from the page, and a saturated one separates itself. */
		background: var(--salient-color);
		/* Deliberately no `overflow: clip`: the overflow menu's panel has to escape this
		   box. `position: sticky` above already makes this the containing block it is
		   positioned against, so opening the menu cannot change this bar's own height —
		   which matters, because that height is what `--page-header-height` carries. */
	}

	/* The line of words, and exactly one line tall. The height is what makes the centring
	   above mean what it looks like it means: left to its content this box is as tall as
	   its tallest item, and "Website"'s 🌐 hangs below the baseline, so centring the BOX
	   would sit every word about 3.5px above the middle of the band. Sized from the font
	   the links are set in rather than from a number, so it follows `--small-font-size`.
	   The 🌐 and the ☰ overflow this box by design; the nav clips nothing. */
	.row {
		display: flex;
		flex-direction: row;
		flex-wrap: nowrap;
		align-items: baseline;
		gap: var(--spacing);
		width: 100%;
		/* A flex item's floor is its content, not zero, and `.area` cannot shrink below a
		   parent that will not. */
		min-width: 0;
		font-size: var(--small-font-size);
		height: 1lh;
	}

	/* A chip in the bar's own colours, inverted, since the bar is already turquoise. `a`
	   in the selector so it outranks the white every link in the bar is given below. */
	.bar a.chip {
		flex: none;
		color: var(--salient-color);
		background: var(--background-color);
		border-radius: var(--roundedness);
		padding: 0 var(--spacing-half);
		font-size: var(--extra-small-font-size);
		text-decoration: none;
	}

	/* The one item here with no length limit worth relying on, so it is the one allowed to
	   shrink — and therefore the one that has to be pinned while Overflow measures. Without
	   the second rule the bar absorbs every pixel of overflow by grinding this label down,
	   never reports being full, and no link ever collapses. */
	.area {
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
	   drops the whole rule as unused — silently, and with it the freeze. It is written on
	   whichever element is passed to `Overflow` as its row, which is `.row` and not the
	   nav — moving it and leaving this selector behind would drop the freeze just as
	   quietly as the pruner would. */
	:global(.row[data-fitting]) .area {
		flex-shrink: 0;
	}

	/* White on the turquoise, the way Banner.svelte does it and for the same reason: the
	   colours a link inherits are chosen against the page's own ground and do not survive
	   a saturated one. The third rule is the one that is easy to miss — Link.svelte paints
	   the route you are on with `--text-color`, which is black. */
	.bar :global(a) {
		color: var(--background-color);
	}

	/* ...except inside the overflow panel, which is its own surface. Left white-on-white
	   the open menu was simply blank. Painting the panel to match the bar keeps one rule
	   for the links and makes the menu read as part of the bar it drops out of. */
	.bar :global([data-overflow-panel]) {
		background: var(--salient-color);
		border-color: var(--background-color);
	}

	.bar :global(a .underline) {
		text-decoration-color: var(--background-color);
	}

	.bar :global(a[aria-current]) {
		color: var(--background-color);
	}

	/* Which leaves the app's own convention to say where you are: every other link keeps
	   its underline, and the current one drops it. No new tab vocabulary. */

	/* The overflow toggle is a faded-turquoise chip by default, which is invisible on
	   turquoise. It is a glyph rather than a word, so it centres in the row rather than
	   sitting on the baseline the words share. */
	.bar :global(button) {
		background: transparent;
		color: var(--background-color);
		align-self: center;
	}

	/* The home link's own box, so that the name below can be a BLOCK and still sit on the
	   row's baseline. A clipped box has to stop being inline-level for that to be possible
	   at all, and a block only gets a baseline its parent can use if its parent is looking
	   for one — hence the flex context here rather than one level up on `.area`, which
	   lands the baseline just as well and grows the bar from 48px to 64px. This bar's
	   height IS `--page-header-height`, so that is disqualifying rather than untidy.

	   A flex container ignores `vertical-align` on its items, so the 📚 `Link` appends
	   stops hanging below the text and sits on the baseline with it, about two pixels up.
	   That is the intended reading: the glyph belongs to the venue's name. "Website"'s 🌐
	   is a different link and still hangs, where it marks a link that leaves the site. */
	.bar .area :global(a) {
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
