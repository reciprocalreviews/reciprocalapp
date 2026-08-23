<script lang="ts">
	/** The Reciprocal Reviews brand mark: two arrows chasing each other around a circle,
	 * echoing 🔄 — reciprocity, the thing the platform is about.
	 *
	 * Deliberately not a `Label` like the others in Labels.ts. Those are Unicode glyphs
	 * that name a *kind of thing* (★ is a review token, 📚 a venue); this names the
	 * platform itself, and no character in Noto Emoji says that. It is also the one mark
	 * that leaves the app — Google Workspace, the GitHub org, the newsletter — so it has
	 * to exist as a file too. `static/logo.svg` is the same geometry with the teal baked
	 * in; keep the two in sync.
	 *
	 * Colored with `currentColor` so it inherits: white against the teal `h1` bar in the
	 * page header, salient teal anywhere on a page background. */

	let {
		size = '1em',
		shadow = true
	}: {
		/** Any CSS length. Defaults to 1em so the mark scales with whatever text it sits in. */
		size?: string;
		/** The offset ghost beneath the arrows — part of the mark, so it is on by
		 * default and every rendering of the logo carries it. The one exception is
		 * the favicon (static/brand/favicon.svg), which renders at 16–32px where the
		 * 3% offset is literally sub-pixel and only blurs the strokes. */
		shadow?: boolean;
	} = $props();

	const ARROWS = [
		'M 42.49 78.01 L 39.65 88.64 A 40 40 0 0 1 33.10 13.75 L 28.66 4.23 L 50.60 15.51 L 42.18 33.23 L 37.74 23.72 A 29 29 0 0 0 42.49 78.01 Z',
		'M 57.51 21.99 L 60.35 11.36 A 40 40 0 0 1 66.90 86.25 L 71.34 95.77 L 49.40 84.49 L 57.82 66.77 L 62.26 76.28 A 29 29 0 0 0 57.51 21.99 Z'
	];
</script>

<!-- A brand mark next to the wordmark it belongs to is decorative: the name is already
     right there in text, so announcing it again would just repeat it to a screen reader. -->
<svg
	width={size}
	height={size}
	viewBox="0 0 100 100"
	fill="currentColor"
	aria-hidden="true"
	focusable="false"
	data-testid="logo"
	xmlns="http://www.w3.org/2000/svg"
>
	{#if shadow}
		<g opacity="0.28" transform="translate(3 3.5)">
			{#each ARROWS as d}<path {d} />{/each}
		</g>
	{/if}
	{#each ARROWS as d}<path {d} />{/each}
</svg>

<style>
	svg {
		/* The page header's h1 is a flex row, but the mark is also used in prose; keep it
		   sitting on the text baseline rather than hanging below it. */
		vertical-align: -0.125em;
		flex-shrink: 0;
	}
</style>
