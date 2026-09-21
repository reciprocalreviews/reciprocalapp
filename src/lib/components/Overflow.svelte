<script lang="ts" generics="Item">
	import { page } from '$app/state';
	import type LocaleText from '$lib/locales/Locale';
	import type { ButtonText } from '$lib/locales/Locale';
	import { getLocaleContext } from '$routes/Contexts';
	import { untrack, type Snippet } from 'svelte';
	import { clickOutside } from './clickOutside';
	import { fits } from './fit';

	/**
	 * Items that stay in a row of chrome while there is room for them, and collapse behind
	 * one control when there is not.
	 *
	 * Both bands of chrome used `flex-wrap: wrap`, which meant a narrow screen answered a
	 * crowded row by growing a second one — so the fixed header took nearly half the
	 * viewport on a phone, which is the problem #176 is about.
	 *
	 * **A measurement decides, and the breakpoint is demoted to the server's guess.** The
	 * first version of this decided entirely by `max-width: 48rem`, which collapsed every
	 * link at 700px although the row had room for all of them — and no single number could
	 * be right anyway, since an admin's venue bar carries six links and a stranger's carries
	 * three. The query survives only as `.pending` below, because the browser paints the
	 * server's HTML before any of this runs and a guess that is right at both extremes
	 * beats no guess at all.
	 *
	 * Four things about the shape are load-bearing:
	 *
	 * 1. **One list, split — never two copies.** Items arrive as data and render through
	 *    one snippet into one of two keyed blocks over disjoint slices, so each exists
	 *    exactly once. A version that rendered an inline copy and a menu copy would put two
	 *    elements behind every test id in the chrome, which is a Playwright strict-mode
	 *    failure rather than an ambiguity it resolves. Order is priority: the last item is
	 *    the first to collapse.
	 *
	 * 2. **The closed panel is hidden with `visibility`, not `display`.** A `display: none`
	 *    panel is not laid out, so the items in it would have no width — and reading their
	 *    widths where they already are is exactly what lets this split one list instead of
	 *    keeping a hidden measuring copy. `visibility: hidden` is still out of the
	 *    accessibility tree, out of the tab order, and out of Playwright's idea of visible.
	 *
	 * 3. **The panel is absolutely positioned**, and so is the control while it is idle.
	 *    `Nav.svelte`'s measured height feeds `--nav-height` and `VenueBar`'s feeds
	 *    `--page-header-height`, which are the sticky offsets for everything below them, so
	 *    nothing here may take part in the row's height. The control is laid out even when
	 *    it is not offered, so its width is known BEFORE it is needed — measuring it only
	 *    once it appeared would reintroduce `fit.ts`'s off-by-one somewhere no test reaches.
	 *
	 * 4. **The row is told to stop shrinking for the length of a measurement.** Everything
	 *    in these rows that can absorb — a breadcrumb, a venue's name, the spacer that
	 *    pushes the account group right — grinds itself down instead of letting the row
	 *    report that it is full, which is why `scrollWidth > clientWidth` is useless here.
	 *    The `data-fitting` attribute is written and removed inside one synchronous read, so
	 *    no frame is ever painted in that state, and each call site pins its own shrinkables
	 *    under it. **A shrinkable child with no `[data-fitting]` rule silently stops this
	 *    component working**, with no error and no tell at desktop width.
	 *
	 * `<details>` was an alternative and cannot do (1): its content is hidden when closed,
	 * and revealing it at wide widths needs `::details-content`, not yet baseline. A
	 * `popover` handles (3) natively but needs CSS anchor positioning to sit under its own
	 * button, which is still landing in Safari and Firefox.
	 *
	 * The tradeoff, stated rather than discovered: with scripting off the collapsed items
	 * cannot be reached below the breakpoint. Unchanged from before, and the app already
	 * needs hydration to do anything at all.
	 */
	let {
		strings,
		items,
		key,
		item,
		row,
		testid = undefined
	}: {
		/** Names the control for a screen reader — "Site menu", "Venue menu". */
		strings: (l: LocaleText) => ButtonText;
		/** In the order they may be given up: the LAST collapses first. */
		items: Item[];
		key: (item: Item) => string;
		item: Snippet<[Item]>;
		/**
		 * The flex row whose width decides. A prop rather than something discovered, because
		 * it is not always this component's parent: in `Nav.svelte` these items sit inside
		 * `.authenticated`, but whether they fit is a fact about `.nav`.
		 */
		row: HTMLElement | undefined;
		testid?: string;
	} = $props();

	const locale = getLocaleContext();
	const text = $derived(strings(locale()));

	let open = $state(false);

	/** How many leading items stay in the row. Null until the first measurement. */
	let kept = $state<number | null>(null);
	/** Whether a measurement has happened yet; until it has, `.pending` CSS is the guess. */
	let fitted = $state(false);
	/** Clamped, because `kept` outlives an `items` array that shrinks on sign-out. */
	const visible = $derived(kept === null ? items.length : Math.min(kept, items.length));

	let inline = $state<HTMLDivElement | undefined>(undefined);
	let menu = $state<HTMLDivElement | undefined>(undefined);
	let toggle = $state<HTMLButtonElement | undefined>(undefined);
	let panel = $state<HTMLDivElement | undefined>(undefined);

	/** Re-entrancy guard: a measurement writes an attribute, and an attribute can wake the
	 * observers that asked for the measurement. */
	let measuring = false;
	/** The key of the item that held focus when a split moved it; see the effect below. */
	let displaced: string | null = null;

	/** The box these items are actually flex items of. `.inline` is `display: contents`, so
	 * it generates none of its own. */
	function layoutParent(node: HTMLElement): HTMLElement | null {
		let parent = node.parentElement;
		while (parent !== null && getComputedStyle(parent).display === 'contents')
			parent = parent.parentElement;
		return parent;
	}

	function fit() {
		if (measuring) return;
		const container = menu ? layoutParent(menu) : null;
		if (row === undefined || !inline || !menu || !panel || container === null) return;

		measuring = true;
		try {
			// Every item is measurable wherever it currently lives; see (2) above.
			const widths = [...inline.children, ...panel.children].map(
				(node) => node.getBoundingClientRect().width
			);
			const toggleWidth = menu.getBoundingClientRect().width;
			const gap = Number.parseFloat(getComputedStyle(container).columnGap) || 0;

			row.setAttribute('data-fitting', '');
			let next: number;
			try {
				const style = getComputedStyle(row);
				const available =
					row.getBoundingClientRect().width -
					Number.parseFloat(style.paddingInlineStart) -
					Number.parseFloat(style.paddingInlineEnd);

				// The span of the row's children by their edges, rather than `scrollWidth`:
				// browsers disagree about whether `scrollWidth` includes end padding, and that
				// disagreement lands exactly on the boundary being decided here. A
				// `display: contents` child generates no box and reports an empty rect at the
				// origin, which would drag the start edge to zero.
				let start = Number.POSITIVE_INFINITY;
				let end = Number.NEGATIVE_INFINITY;
				/**
				 * Walk the row's flex items, descending through anything that generates no box
				 * of its own. `.inline` is `display: contents`, so the items ARE flex items of
				 * the row but are not among `row.children` as boxes — a walk that skipped it
				 * measured a row that contained almost nothing and concluded that everything
				 * fitted at every width.
				 *
				 * Out-of-flow children are skipped, and that is not a nicety either: the idle
				 * control is absolutely positioned at the row's end precisely so its width can
				 * be read before it is offered, which puts its right edge at the far side of
				 * however wide the row happens to be. Counted, it made `base` grow with the
				 * viewport, so a wider row measured as needing more and gave up a link that a
				 * narrower one had kept.
				 */
				const span_of = (parent: Element) => {
					for (const child of parent.children) {
						if (child.getClientRects().length === 0) {
							span_of(child);
							continue;
						}
						if (getComputedStyle(child).position === 'absolute') continue;
						const rect = child.getBoundingClientRect();
						start = Math.min(start, rect.left);
						end = Math.max(end, rect.right);
					}
				};
				span_of(row);
				const span = end > start ? end - start : 0;

				// What the row needs for everything that is not one of these items, found by
				// subtracting out the current split rather than by summing the other children
				// — they are not this component's to enumerate, and some of them are nested.
				// Because it does not depend on the split, `fit()` is idempotent: a pass it
				// provokes in an observer computes the same answer and writes nothing.
				const base =
					span -
					widths.slice(0, visible).reduce((total, width) => total + width + gap, 0) -
					(visible < items.length ? toggleWidth + gap : 0);

				next = fits({ available, base, widths, toggle: toggleWidth, gap });
			} finally {
				row.removeAttribute('data-fitting');
			}

			fitted = true;
			if (next === visible) return;

			const active = document.activeElement;
			const owner = active instanceof HTMLElement ? active.closest('[data-overflow-key]') : null;
			displaced = owner instanceof HTMLElement ? (owner.dataset.overflowKey ?? null) : null;
			kept = next;
		} finally {
			measuring = false;
		}
	}

	// Re-fit when the items change (signing in adds Profile and Logout), when the route
	// changes (`Link` drops the current page's underline, a few pixels narrower), and when
	// the locale relabels everything. `visible` is deliberately not read: `fit` writes it,
	// and an effect that both read and wrote it would re-run itself forever.
	$effect(() => {
		items.map(key).join('\u0000');
		page.url.pathname;
		text;
		untrack(fit);
	});

	$effect(() => {
		if (row === undefined || !menu) return;
		const observer = new ResizeObserver(() => untrack(fit));
		// The row, for the viewport. And the box these items are flex items of, because the
		// things beside them change width on their own: the balance gains a digit, the
		// pending-actions widget appears.
		observer.observe(row);
		const container = layoutParent(menu);
		if (container !== null && container !== row) observer.observe(container);

		// Every width here is provisional until the web fonts land. `ready` covers the
		// self-hosted faces; `loadingdone` covers the Google stylesheet, which app.html
		// starts with `media="print"` and promotes on load, so its fetch can begin after
		// `ready` has already resolved.
		let live = true;
		const refit = () => {
			if (live) fit();
		};
		document.fonts?.ready.then(refit);
		document.fonts?.addEventListener('loadingdone', refit);
		return () => {
			live = false;
			observer.disconnect();
			document.fonts?.removeEventListener('loadingdone', refit);
		};
	});

	// A keyed block destroys and rebuilds an item when it crosses between row and panel, so
	// an item that held focus loses it silently. It can only happen on a resize, a font swap
	// or a sign-in — never as the result of a click — but landing on <body> says nothing, so
	// hand focus to the control that now owns the item: it announces itself and says how to
	// get back to it.
	$effect(() => {
		visible;
		untrack(() => {
			if (displaced === null) return;
			const moved = displaced;
			displaced = null;
			const node = inline?.querySelector(`[data-overflow-key="${CSS.escape(moved)}"]`);
			const focusable =
				node instanceof HTMLElement
					? node.querySelector<HTMLElement>('a[href], button:not([disabled])')
					: null;
			if (focusable) focusable.focus();
			else toggle?.focus();
		});
	});

	/**
	 * Close on navigation, so following a link out of the menu does not leave it hanging
	 * open over the page that arrives.
	 *
	 * An `$effect` in chrome, which this codebase is otherwise careful about — but this one
	 * is the safe kind. It cannot run during SSR, it only ever closes a menu that a reader
	 * opened after hydration, and it writes no layout.
	 */
	$effect(() => {
		page.url.pathname;
		untrack(() => (open = false));
	});
</script>

<!-- Escape on the window rather than on a wrapper, so it closes the menu wherever focus has
     got to inside the open panel — and so nothing here needs an interaction handler on a
     plain container, or an invented ARIA role to justify one. -->
<svelte:window
	onkeydown={(event) => {
		if (event.key === 'Escape' && open) open = false;
	}}
/>

<div class="inline" class:pending={!fitted} bind:this={inline}>
	{#each items.slice(0, visible) as entry (key(entry))}
		<div class="item" data-overflow-key={key(entry)}>{@render item(entry)}</div>
	{/each}
</div>

<div
	class="menu"
	class:idle={visible === items.length}
	class:open
	class:pending={!fitted}
	bind:this={menu}
	use:clickOutside={() => (open = false)}
>
	<button
		type="button"
		class="toggle"
		bind:this={toggle}
		aria-expanded={open}
		title={text.tip}
		aria-label={text.tip}
		data-testid={testid}
		onclick={() => (open = !open)}>☰</button
	>
	<!-- `data-overflow-panel` is a deliberate hook, not decoration: the panel is a surface
	     of its own, and a row with a coloured ground has to be able to say what this one
	     looks like. Without it the venue bar's white-on-turquoise link colour applied here
	     too, over a white panel, and the open menu was blank. -->
	<div class="panel" data-overflow-panel bind:this={panel}>
		{#each items.slice(visible) as entry (key(entry))}
			<div class="item" data-overflow-key={key(entry)}>{@render item(entry)}</div>
		{/each}
	</div>
</div>

<style>
	/* No box of its own: the items become flex items of whichever row this sits in, so they
	   take that row's gap and alignment exactly as if this component were not here. */
	.inline {
		display: contents;
	}

	.item {
		display: inline-flex;
		align-items: center;
		flex: none;
		white-space: nowrap;
	}

	.panel .item {
		display: block;
	}

	.menu {
		flex: none;
		position: relative;
		display: flex;
		align-items: center;
		/* This box is the row's flex item, not the ☰ inside it, so this is where a row
		   aligned on baselines has to be told that the control is a glyph rather than a
		   word. Said on the button instead, it only centred the button within this box and
		   left the control in the baseline group — which in a row of words pushed every one
		   of them down by the difference between its ascent and theirs. Harmless in a row
		   that centres its items, which is what the site header does. */
		align-self: center;
	}

	/* Nothing is collapsed, so the control is not offered — but it stays laid out, out of
	   flow at the row's end, so its width is known before it is ever needed. See (3). */
	.menu.idle {
		position: absolute;
		inset-inline-end: 0;
		visibility: hidden;
		pointer-events: none;
	}

	/* An empty absolutely-positioned panel at `top: 100%` would otherwise add its height to
	   every page's scrollHeight. */
	.menu.idle .panel {
		display: none;
	}

	.toggle {
		font-family: var(--font-face);
		font-size: var(--small-font-size);
		line-height: 1;
		cursor: pointer;
		background: var(--salient-color-faded);
		color: var(--foreground-color);
		border: none;
		border-radius: var(--roundedness);
		padding: var(--spacing-half);
		flex: none;
	}

	.toggle:focus {
		outline: var(--focus-color) solid var(--thick-border-width);
	}

	.panel {
		position: absolute;
		top: 100%;
		inset-inline-end: 0;
		z-index: 3;
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: var(--spacing);
		white-space: nowrap;
		/* It grows leftward from the row's end, and a long label must not push the document
		   wider than the viewport — a sticky row in a document that scrolls sideways slides
		   out of view (#156). */
		max-width: calc(100vw - var(--spacing) * 2);
		background: var(--background-color);
		border: var(--border-color) solid var(--border-width);
		border-radius: var(--roundedness);
		padding: var(--spacing);
		box-shadow: 2px 3px 0 rgba(0, 0, 0, 0.2);
		/* Hidden but laid out; see (2) above. */
		visibility: hidden;
	}

	.menu.open .panel {
		visibility: visible;
	}

	/* The server's guess, and only that. The browser paints the server's HTML before any
	   measurement can run, so without this a phone paints the whole row and then collapses
	   it — a horizontal flash on every first load. The guess is right at both extremes and
	   wrong only between 48rem and wherever the row actually runs out, which is the band
	   this change exists to fix and the one place a single reflow at hydration is the point
	   rather than the bug. */
	@media (max-width: 48rem) {
		.inline.pending {
			display: none;
		}

		.menu.pending {
			position: relative;
			inset-inline-end: auto;
			visibility: visible;
			pointer-events: auto;
		}

		.menu.pending .panel {
			display: flex;
		}
	}
</style>
